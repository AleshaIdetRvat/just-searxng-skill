#!/usr/bin/env bash
#
# search.sh — web search via a local SearXNG instance.
#
# Ensures SearXNG is up (auto-launches a local container on first use), sends
# one JSON search request, and prints clean, ranked results for an agent to read.
#
# Usage:
#   search.sh "your query" [options]
#
# Options:
#   -n, --num N            max results (default 10)
#   -c, --categories LIST  e.g. general | news | images | science | it | videos
#   -e, --engines LIST     e.g. google,duckduckgo,brave  (comma-separated)
#   -l, --lang CODE        e.g. en | ru | de | zh-CN     (default: all)
#   -t, --time-range R     day | week | month | year
#   -s, --safesearch N     0 (off) | 1 | 2 (strict)      (default 0)
#   -p, --page N           result page number (default 1)
#       --urls-only        print only result URLs (one per line; pipe to a fetcher)
#       --json             print the raw SearXNG JSON response
#   -h, --help             show this help
#
# Env: SEARXNG_URL, SEARXNG_PORT — see ensure-searxng.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UA="Mozilla/5.0 (compatible; searxng-agent-skill)"

usage() { sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- parse args -----------------------------------------------------------
QUERY=""
NUM=10; CATEGORIES=""; ENGINES=""; LANG=""; TIME_RANGE=""; SAFESEARCH="0"; PAGE="1"
MODE="text"   # text | urls | json

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--num)         NUM="${2:?}"; shift 2 ;;
    -c|--categories)  CATEGORIES="${2:?}"; shift 2 ;;
    -e|--engines)     ENGINES="${2:?}"; shift 2 ;;
    -l|--lang|--language) LANG="${2:?}"; shift 2 ;;
    -t|--time-range)  TIME_RANGE="${2:?}"; shift 2 ;;
    -s|--safesearch)  SAFESEARCH="${2:?}"; shift 2 ;;
    -p|--page|--pageno) PAGE="${2:?}"; shift 2 ;;
    --urls-only)      MODE="urls"; shift ;;
    --json)           MODE="json"; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; QUERY="${QUERY:-${1:-}}"; break ;;
    -*)               echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)                if [ -z "$QUERY" ]; then QUERY="$1"; else QUERY="$QUERY $1"; fi; shift ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "ERROR: no query given." >&2
  usage >&2
  exit 2
fi

# --- ensure SearXNG is up (auto-launch if needed) -------------------------
# ensure-searxng.sh prints the resolved base URL to stdout on success and
# actionable guidance to stderr on failure; forward both faithfully.
BASE_URL="$("${SCRIPT_DIR}/ensure-searxng.sh")" && ENSURE_CODE=0 || ENSURE_CODE=$?
if [ "$ENSURE_CODE" -ne 0 ]; then
  echo "" >&2
  echo "Search aborted: SearXNG is not available (see the message above)." >&2
  exit "$ENSURE_CODE"
fi
BASE_URL="${BASE_URL%/}"

# --- build and send the request ------------------------------------------
set -- -G "${BASE_URL}/search" \
       --data-urlencode "q=${QUERY}" \
       --data-urlencode "format=json" \
       --data-urlencode "pageno=${PAGE}" \
       --data-urlencode "safesearch=${SAFESEARCH}"
[ -n "$CATEGORIES" ] && set -- "$@" --data-urlencode "categories=${CATEGORIES}"
[ -n "$ENGINES" ]    && set -- "$@" --data-urlencode "engines=${ENGINES}"
[ -n "$LANG" ]       && set -- "$@" --data-urlencode "language=${LANG}"
[ -n "$TIME_RANGE" ] && set -- "$@" --data-urlencode "time_range=${TIME_RANGE}"

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
HTTP_CODE="$(curl -sS --max-time 25 -A "$UA" -o "$TMP" -w '%{http_code}' "$@" || echo "000")"

if [ "$HTTP_CODE" = "000" ]; then
  echo "ERROR: could not reach SearXNG at ${BASE_URL} (connection failed/timeout)." >&2
  exit 4
fi
if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: SearXNG returned HTTP ${HTTP_CODE} for this query." >&2
  case "$HTTP_CODE" in
    403|429) echo "  Likely the bot limiter is blocking requests. This skill's config disables it;" >&2
             echo "  if you're using a custom/remote instance, set server.limiter: false there." >&2 ;;
    *)       echo "  First 300 bytes of the response:" >&2; head -c 300 "$TMP" | sed 's/^/    /' >&2; echo >&2 ;;
  esac
  exit 4
fi

# --- raw JSON mode --------------------------------------------------------
if [ "$MODE" = "json" ]; then
  if command -v jq >/dev/null 2>&1; then jq . <"$TMP"; else cat "$TMP"; fi
  exit 0
fi

# --- format results (jq preferred, python3 fallback) ----------------------
format_with_jq() {
  jq -r --argjson num "$NUM" --arg mode "$MODE" '
    def clip($n): if (.|length) > $n then (.[0:$n] + "…") else . end;
    def unresp: (.unresponsive_engines // [])
      | map(if type=="array" then (.[0] + (if (.[1]//"")!="" then ": " + (.[1]|tostring) else "" end)) else tostring end);
    if ($mode == "urls") then
      (.results[:$num][] | .url)
    else
      ( (.answers // []) as $a
        | (if ($a|length) > 0 then "Answer: " + ($a | map(if type=="object" then (.answer // .content // tostring) else tostring end) | join(" | ")) + "\n" else "" end)
      ) as $ans
      | $ans +
      ( if ((.results // []) | length) == 0 then
          ( if (unresp|length) > 0 then
              "No results — every queried engine was temporarily unavailable:\n"
              + (unresp | map("    - " + .) | join("\n"))
              + "\n  Wait ~30–60s and retry, or pass different --engines / --categories."
            else "No results found for: " + (.query // "")
              + "\n  Try rephrasing, broadening the query, or a different --category." end )
        else
          ( .results[:$num] | to_entries
            | map(
                "[\(.key + 1)] \(.value.title // "(no title)")"
                + "\n    \(.value.url // "")"
                + ( (.value.content // "") | gsub("\\s+";" ") | ltrimstr(" ")
                    | if . == "" then "" else "\n    " + clip(240) end )
                + ( ((.value.engines // []) | join(",")) as $e
                    | if $e == "" then "" else "\n    [\($e)]" end )
              )
            | join("\n\n")
          )
        end )
    end
  ' <"$TMP"
}

format_with_python() {
  python3 - "$NUM" "$MODE" "$TMP" <<'PY'
import json, sys, re
num = int(sys.argv[1]); mode = sys.argv[2]
with open(sys.argv[3], encoding="utf-8") as fh:
    data = json.load(fh)
results = (data.get("results") or [])[:num]
if mode == "urls":
    print("\n".join(r.get("url", "") for r in results)); sys.exit(0)
out = []
answers = data.get("answers") or []
if answers:
    def a(x): return x if isinstance(x, str) else (x.get("answer") or x.get("content") or str(x))
    out.append("Answer: " + " | ".join(a(x) for x in answers))
if not results:
    unresp = data.get("unresponsive_engines") or []
    if unresp:
        def fmt(e):
            e = e if isinstance(e, (list, tuple)) else [e]
            return e[0] + ((": " + str(e[1])) if len(e) > 1 and e[1] else "")
        out.append("No results — every queried engine was temporarily unavailable:\n"
                   + "\n".join("    - " + fmt(e) for e in unresp)
                   + "\n  Wait ~30–60s and retry, or pass different --engines / --categories.")
    else:
        out.append("No results found for: " + (data.get("query") or "")
                   + "\n  Try rephrasing, broadening the query, or a different --category.")
for i, r in enumerate(results, 1):
    block = ["[%d] %s" % (i, r.get("title") or "(no title)"), "    " + (r.get("url") or "")]
    c = re.sub(r"\s+", " ", (r.get("content") or "")).strip()
    if c:
        block.append("    " + (c[:240] + "…" if len(c) > 240 else c))
    eng = ",".join(r.get("engines") or [])
    if eng:
        block.append("    [%s]" % eng)
    out.append("\n".join(block))
print("\n\n".join(out))
PY
}

if command -v jq >/dev/null 2>&1; then
  format_with_jq
elif command -v python3 >/dev/null 2>&1; then
  format_with_python
else
  echo "ERROR: neither 'jq' nor 'python3' is available to parse results." >&2
  echo "  Install one (e.g. 'brew install jq' / 'apt-get install -y jq'), or use --json for raw output." >&2
  exit 5
fi
