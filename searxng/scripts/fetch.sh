#!/usr/bin/env bash
#
# fetch.sh — fetch a web page and extract clean, readable article text.
#
# Companion to search.sh: search finds candidate URLs, fetch reads the ones you
# actually need. Downloads the page with curl and runs Mozilla Readability (the
# Firefox Reader View extractor) to strip nav, ads, sidebars and boilerplate,
# leaving just the main content — a big token saving over raw HTML.
#
# Usage:
#   fetch.sh "https://example.com/article" [options]
#
# Options:
#   -n, --max-chars N   truncate output to N characters (default 100000)
#   -t, --timeout SEC   HTTP timeout in seconds (default 25)
#       --html          output Readability's cleaned HTML instead of plain text
#       --json          output raw JSON {url,title,byline,excerpt,length,text}
#   -h, --help          show this help
#
# On first use it installs its reader dependencies (Node) automatically.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER_DIR="${SCRIPT_DIR}/reader"
UA="Mozilla/5.0 (compatible; searxng-agent-skill)"

usage() {
  cat <<'EOF'
fetch.sh — fetch a web page and extract clean, readable article text.

Usage:
  fetch.sh "https://example.com/article" [options]

Options:
  -n, --max-chars N   truncate output to N characters (default 100000)
  -t, --timeout SEC   HTTP timeout in seconds (default 25)
      --html          output Readability's cleaned HTML instead of plain text
      --json          output raw JSON {url,title,byline,excerpt,length,text}
  -h, --help          show this help
EOF
}

# --- parse args -----------------------------------------------------------
URL=""
MAXCHARS="100000"; TIMEOUT="25"; MODE="text"

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--max-chars)   MAXCHARS="${2:?}"; shift 2 ;;
    -t|--timeout)     TIMEOUT="${2:?}"; shift 2 ;;
    --html)           MODE="html"; shift ;;
    --json)           MODE="json"; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; URL="${URL:-${1:-}}"; break ;;
    -*)               echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)                if [ -z "$URL" ]; then URL="$1"; fi; shift ;;
  esac
done

if [ -z "$URL" ]; then
  echo "ERROR: no URL given." >&2
  usage >&2
  exit 2
fi
case "$URL" in
  http://*|https://*) : ;;
  *) echo "ERROR: URL must start with http:// or https:// — got: ${URL}" >&2; exit 2 ;;
esac

# --- ensure Node + reader deps (auto-install on first use) ----------------
# Node is commonly installed via nvm with lazy loading, so `node` is a shell
# function that a non-interactive script doesn't inherit. If plain `node` isn't
# on PATH, fall back to the nvm default (or newest) install and add its bin dir
# — which also makes npm/npx resolvable for the deps install below.
if ! command -v node >/dev/null 2>&1; then
  NVM_ROOT="${NVM_DIR:-$HOME/.nvm}"
  if [ -d "${NVM_ROOT}/versions/node" ]; then
    _ver=""; [ -f "${NVM_ROOT}/alias/default" ] && _ver="$(cat "${NVM_ROOT}/alias/default" 2>/dev/null)"
    _bindir=""
    if [ -n "$_ver" ] && [ -x "${NVM_ROOT}/versions/node/v${_ver#v}/bin/node" ]; then
      _bindir="${NVM_ROOT}/versions/node/v${_ver#v}/bin"
    else
      _latest="$(ls "${NVM_ROOT}/versions/node" 2>/dev/null | sort -V | tail -1)"
      [ -n "$_latest" ] && [ -x "${NVM_ROOT}/versions/node/${_latest}/bin/node" ] && _bindir="${NVM_ROOT}/versions/node/${_latest}/bin"
    fi
    [ -n "$_bindir" ] && export PATH="${_bindir}:${PATH}"
  fi
fi
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: 'node' is required to extract readable text but was not found." >&2
  echo "  Install Node.js 18+ (https://nodejs.org), then re-run." >&2
  echo "  (If you use nvm, set a default so scripts can find it: 'nvm alias default node'.)" >&2
  echo "  You can still get raw search results from search.sh without Node." >&2
  exit 5
fi
if [ ! -d "${READER_DIR}/node_modules" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: reader dependencies aren't installed and 'npm' was not found." >&2
    echo "  Install Node.js/npm, then run: (cd \"${READER_DIR}\" && npm install)" >&2
    exit 5
  fi
  echo "First run: installing reader dependencies in ${READER_DIR} (one-time)..." >&2
  if ! ( cd "${READER_DIR}" && npm install --silent --no-audit --no-fund ) >&2; then
    echo "ERROR: 'npm install' failed in ${READER_DIR}." >&2
    echo "  Fix the error above, or install manually: (cd \"${READER_DIR}\" && npm install)" >&2
    exit 5
  fi
fi

# --- fetch the page -------------------------------------------------------
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
META="$(curl -sS -L --max-time "$TIMEOUT" -A "$UA" \
          -H 'Accept: text/html,application/xhtml+xml,*/*' \
          -o "$TMP" -w '%{http_code} %{content_type}' "$URL" || echo "000 -")"
HTTP_CODE="${META%% *}"
CTYPE="${META#* }"

if [ "$HTTP_CODE" = "000" ]; then
  echo "ERROR: could not fetch ${URL} (connection failed or timed out after ${TIMEOUT}s)." >&2
  exit 4
fi
if [ "$HTTP_CODE" -ge 400 ] 2>/dev/null; then
  echo "ERROR: server returned HTTP ${HTTP_CODE} for ${URL}." >&2
  case "$HTTP_CODE" in
    403|429) echo "  The site may be blocking automated requests (anti-bot). This skill" >&2
             echo "  fetches with a plain curl and doesn't bypass such protections." >&2 ;;
  esac
  exit 4
fi

# Reject obviously non-HTML payloads (PDF, images, archives) before parsing.
case "$CTYPE" in
  *html*|*xml*|text/plain*|-|"") : ;;
  application/json*) : ;;
  *) echo "ERROR: ${URL} is not an HTML page (content-type: ${CTYPE})." >&2
     echo "  fetch.sh extracts readable text from web pages, not binary files." >&2
     exit 4 ;;
esac

# --- extract --------------------------------------------------------------
node "${READER_DIR}/extract.mjs" --url "$URL" --mode "$MODE" --max-chars "$MAXCHARS" < "$TMP"
