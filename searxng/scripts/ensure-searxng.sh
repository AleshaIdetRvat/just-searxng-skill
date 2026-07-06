#!/usr/bin/env bash
#
# ensure-searxng.sh — make sure a local SearXNG instance is up and answering
# JSON, starting it in a container if needed. Idempotent: safe to call before
# every search. STDOUT carries only the resolved base URL on success; STDERR
# carries errors and one-time guidance. Progress/status logs are silent by
# default — set SEARXNG_VERBOSE=1 to see them.
#
# Exit codes:
#   0  SearXNG is up and the JSON API works (URL printed to stdout)
#   3  No container runtime available and no instance running (actionable
#      message printed — a human needs to install docker/podman once)
#   4  A runtime exists but the instance failed to start / stay healthy
#   5  Prerequisite missing (curl)
#
# Config via environment (all optional):
#   SEARXNG_URL          full base URL of an already-running instance to use as-is
#   SEARXNG_PORT         host port to expose (default 8888)
#   SEARXNG_IMAGE        container image (default searxng/searxng:latest)
#   SEARXNG_SKILL_HOME   state dir for config (default ~/.cache/searxng-agent-skill)
#   SEARXNG_CONTAINER    container name (default searxng-agent-skill)
#   SEARXNG_VERBOSE      set to 1 to print progress/status logs (default: quiet;
#                        errors and guidance are always shown)
#
set -euo pipefail

# log():  errors and one-time guidance — always shown on STDERR.
# info(): progress/status — shown only when SEARXNG_VERBOSE (or SEARXNG_DEBUG)
#         is set, so the common warm path stays completely silent.
log()  { printf '%s\n' "$*" >&2; }
info() { [ -n "${SEARXNG_VERBOSE:-${SEARXNG_DEBUG:-}}" ] && printf '%s\n' "$*" >&2 || true; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT="${SEARXNG_PORT:-8888}"
IMAGE="${SEARXNG_IMAGE:-searxng/searxng:latest}"
CONTAINER="${SEARXNG_CONTAINER:-searxng-agent-skill}"
STATE_DIR="${SEARXNG_SKILL_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/searxng-agent-skill}"
BASE_URL="${SEARXNG_URL:-http://localhost:${PORT}}"
BASE_URL="${BASE_URL%/}"

# --- prerequisites --------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  log "ERROR: 'curl' is required but not installed."
  log "  Install it (e.g. 'brew install curl' / 'apt-get install -y curl') and retry."
  exit 5
fi

# --- health probe ---------------------------------------------------------
# Returns 0 only if the instance answers AND the JSON API is enabled.
json_ok() {
  local body
  body="$(curl -fsS --max-time 6 -G "${BASE_URL}/search" \
            --data-urlencode "q=ping" -d format=json \
            -A "searxng-agent-skill/health" 2>/dev/null || true)"
  # A JSON response starts with '{' and contains a "results" key.
  case "$body" in
    '{'*results*) return 0 ;;
    *) return 1 ;;
  esac
}

if json_ok; then
  info "SearXNG is already up at ${BASE_URL} (JSON API ok)."
  printf '%s\n' "$BASE_URL"
  exit 0
fi

# If the user pointed SEARXNG_URL at an external instance, we do NOT try to
# launch a container over it — just report the problem.
if [ -n "${SEARXNG_URL:-}" ]; then
  log "ERROR: SEARXNG_URL=${SEARXNG_URL} is set but not answering JSON."
  log "  - Is that instance running and reachable?"
  log "  - Does its settings.yml enable the JSON format? (search.formats must include 'json')"
  log "  Unset SEARXNG_URL to let this skill run a local container instead."
  exit 4
fi

# --- pick a container runtime --------------------------------------------
RUNTIME=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  RUNTIME="docker"
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  RUNTIME="podman"
fi

if [ -z "$RUNTIME" ]; then
  log "SearXNG is not running and no working container runtime was found."
  log ""
  log "This skill runs SearXNG locally in a container. Install ONE of these once:"
  log ""
  if [ "$(uname -s)" = "Darwin" ]; then
    log "  macOS (Docker Desktop):   brew install --cask docker   # then open Docker.app"
    log "  macOS (lightweight CLI):  brew install colima docker && colima start"
    log "  macOS (Podman):           brew install podman && podman machine init && podman machine start"
  else
    log "  Debian/Ubuntu:  sudo apt-get update && sudo apt-get install -y docker.io && sudo systemctl enable --now docker"
    log "  Fedora/RHEL:    sudo dnf install -y podman            # rootless, no daemon"
    log "  Any distro:     https://docs.docker.com/engine/install/"
  fi
  log ""
  log "If Docker/Podman IS installed but its daemon is stopped, start it and retry"
  log "(e.g. open Docker Desktop, or 'colima start', or 'podman machine start')."
  log ""
  log "Then just re-run the search — everything else is automatic."
  exit 3
fi
info "Using container runtime: ${RUNTIME}"

# --- prepare mounted config (enables JSON API + disables limiter) ---------
mkdir -p "$STATE_DIR"
SETTINGS="${STATE_DIR}/settings.yml"
if [ ! -f "$SETTINGS" ]; then
  # generate a secret_key without assuming openssl exists
  if command -v openssl >/dev/null 2>&1; then
    SECRET="$(openssl rand -hex 32)"
  else
    SECRET="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 64)"
    [ -n "$SECRET" ] || SECRET="searxng-agent-skill-$(date +%s)-$$"
  fi
  # sed with a safe delimiter; secret is hex/alnum so no escaping needed
  sed "s|__SECRET_KEY__|${SECRET}|" "${SKILL_DIR}/config/settings.yml" > "$SETTINGS"
  info "Wrote config with generated secret_key -> ${SETTINGS}"
fi

# --- start / create the container ----------------------------------------
container_exists() { $RUNTIME ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; }
container_running() { $RUNTIME ps    --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; }

if container_running; then
  info "Container '${CONTAINER}' is running but not answering yet; waiting for it..."
elif container_exists; then
  info "Starting existing container '${CONTAINER}'..."
  $RUNTIME start "$CONTAINER" >/dev/null
else
  info "Creating container '${CONTAINER}' from ${IMAGE} on port ${PORT}."
  log "First run: pulling the SearXNG image & starting a local container; this can take ~30–60s (later searches are instant)."
  if ! $RUNTIME run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        -p "127.0.0.1:${PORT}:8080" \
        -v "${STATE_DIR}:/etc/searxng" \
        "$IMAGE" >/dev/null 2>"${STATE_DIR}/last-run.err"; then
    log "ERROR: failed to start the SearXNG container. Runtime output:"
    sed 's/^/    /' "${STATE_DIR}/last-run.err" >&2 || true
    log "  Check that the image name is valid and the port ${PORT} is free."
    exit 4
  fi
fi

# --- wait for readiness ---------------------------------------------------
info "Waiting for SearXNG to become ready (up to ~45s)..."
for i in $(seq 1 45); do
  if json_ok; then
    info "SearXNG is ready at ${BASE_URL}."
    printf '%s\n' "$BASE_URL"
    exit 0
  fi
  sleep 1
done

log "ERROR: SearXNG did not become ready in time."
log "  Inspect logs:  ${RUNTIME} logs ${CONTAINER}"
log "  Common causes: image still pulling on a slow link, port ${PORT} in use,"
log "                 or the JSON format is not enabled in ${SETTINGS}."
exit 4
