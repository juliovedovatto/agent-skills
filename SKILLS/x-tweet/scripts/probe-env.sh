#!/usr/bin/env bash
set -u

# probe-env.sh — prerequisite checks → PASS/FAIL table; exit 1 if a required dep is missing.

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PW_CORE="${HOME}/.pi/agent/npm/node_modules/playwright-core/package.json"

check() {
  local name="$1"
  local cmd="$2"
  local desc="$3"
  if eval "$cmd" >/dev/null 2>&1; then
    printf '  %-18s PASS  %s\n' "$name" "$desc"
    return 0
  else
    printf '  %-18s FAIL  %s\n' "$name" "$desc"
    return 1
  fi
}

echo "x-tweet environment probe"
echo "========================="

FAIL=0

check "yt-dlp"    'command -v yt-dlp'    "video download (primary)"      || FAIL=1
check "ffmpeg"    'command -v ffmpeg'    "video merge / transcode"       || FAIL=1
check "ffprobe"   'command -v ffprobe'   "output verification"           || FAIL=1
check "jq"        'command -v jq'        "JSON parsing"                  || FAIL=1
check "curl"      'command -v curl'      "HTTP fetch / t.co expansion"   || FAIL=1
check "python3"   'command -v python3'   "format selector"               || FAIL=1
check "node"      'command -v node'      "URL normalize / render / fetch" || FAIL=1
check "system-chrome" "[ -x '$CHROME' ]"  "headless screenshot backend"   || FAIL=1
check "playwright-core" "[ -f '$PW_CORE' ]" "element-level screenshot"   || true

echo "========================="
if [ "$FAIL" -eq 1 ]; then
  echo "RESULT: FAIL — one or more required dependencies missing"
  exit 1
else
  echo "RESULT: PASS — all required dependencies present"
  exit 0
fi