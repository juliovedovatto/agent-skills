#!/usr/bin/env bash
set -u

# download-video.sh — yt-dlp primary + FxTwitter direct-mp4 fallback + ffprobe verify.
# Usage: download-video.sh <url> [output-dir] [--cookies] [--max-filesize <size>]
# Exit codes: 0 ok | 2 needs-cookies (re-run with --cookies) | 3 tombstone/deleted |
#             4 transient 5xx/rate-limit | 5 no media | 6 ffprobe-fail |
#             7 file exceeds size cap | 1 other

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${HOME}/tmp/.pi"
URL=""
USE_COOKIES=0
MAX_FILESIZE="500M"
POSITIONAL=0

for arg in "$@"; do
  case "$arg" in
    --cookies) USE_COOKIES=1 ;;
    --max-filesize) shift_next=1 ;;
    -h|--help)
      echo "Usage: download-video.sh <url> [output-dir] [--cookies] [--max-filesize <size>]"
      exit 0 ;;
    *)
      if [ "${shift_next:-0}" = "1" ]; then
        MAX_FILESIZE="$arg"
        shift_next=0
      else
        POSITIONAL=$((POSITIONAL + 1))
        if [ "$POSITIONAL" -eq 1 ]; then
          URL="$arg"
        elif [ "$POSITIONAL" -eq 2 ]; then
          OUT_DIR="$arg"
        else
          echo "ERROR: unexpected argument: $arg" >&2
          exit 1
        fi
      fi
      ;;
  esac
done

if [ "${shift_next:-0}" = "1" ]; then
  echo "ERROR: --max-filesize requires a value" >&2
  exit 1
fi

if [ -z "$URL" ]; then
  echo "ERROR: missing <url> argument" >&2
  echo "Usage: download-video.sh <url> [output-dir] [--cookies] [--max-filesize <size>]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# --- Fetch status JSON (always re-fetch — media URLs expire ~7d) ---
STATUS_JSON=$(node "$SCRIPT_DIR/fetch-status.mjs" "$URL" 2>/dev/null)
FETCH_RC=$?
if [ "$FETCH_RC" -ne 0 ]; then
  case "$FETCH_RC" in
    2) echo "ERROR: malformed URL" >&2; exit 2 ;;
    3) echo "ERROR: tweet deleted or unavailable" >&2; exit 3 ;;
    4) echo "ERROR: transient server error, try again later" >&2; exit 4 ;;
    5)
      echo "ERROR: this tweet has no video to download" >&2
      exit 5 ;;
    *) echo "ERROR: fetch-status failed (exit $FETCH_RC)" >&2; exit 1 ;;
  esac
fi

ID=$(echo "$STATUS_JSON" | jq -r '.id')
VIDEO_COUNT=$(echo "$STATUS_JSON" | jq -r '.videos | length')
MEDIA_INDEX=$(echo "$STATUS_JSON" | jq -r '.mediaIndex // empty')
MEDIA_KIND=$(echo "$STATUS_JSON" | jq -r '.mediaKind // empty')

if [ "$VIDEO_COUNT" = "0" ] || [ -z "$VIDEO_COUNT" ] || [ "$VIDEO_COUNT" = "null" ]; then
  echo "ERROR: this tweet has no video to download" >&2
  exit 5
fi

# Select video index — only honor mediaIndex from /video/N, not /photo/N (Mi6)
if [ -n "$MEDIA_INDEX" ] && [ "$MEDIA_KIND" = "video" ]; then
  VID_IDX=$((MEDIA_INDEX - 1))
else
  VID_IDX=0
fi

echo "INFO id=$ID videos=$VIDEO_COUNT selected=$VID_IDX"
echo "INFO max_filesize=$MAX_FILESIZE"

# --- Parse size cap to bytes for post-download enforcement (M2) ---
SIZE_CAP_BYTES=$(echo "$MAX_FILESIZE" | tr -d ' ' | awk '
{
  s = tolower($0)
  if (s ~ /^[0-9]+$/) { print s * 1; exit }
  if (s ~ /^[0-9]+k$/) { sub(/k$/, "", s); print s * 1024; exit }
  if (s ~ /^[0-9]+m$/) { sub(/m$/, "", s); print s * 1048576; exit }
  if (s ~ /^[0-9]+g$/) { sub(/g$/, "", s); print s * 1073741824; exit }
  print 0
}')

# --- Phase 1: yt-dlp primary ---
COOKIES_ARGS=()
if [ "$USE_COOKIES" -eq 1 ]; then
  echo "NOTICE: using Chrome cookies for this download only (consent-gated)" >&2
  COOKIES_ARGS=(--cookies-from-browser chrome)
fi

OUT_TEMPLATE="${OUT_DIR}/${ID}.%(ext)s"
rm -f "${OUT_DIR}/${ID}.mp4" "${OUT_DIR}/${ID}.webm" "${OUT_DIR}/${ID}.mkv"

TMP_DIR="${HOME}/tmp/.pi/.x-tweet-tmp"
mkdir -p "$TMP_DIR"
YTDLP_ERR="${TMP_DIR}/ytdlp-err.$$"
trap 'rm -f "$YTDLP_ERR"' EXIT

# Get format selector from pick-format.py (cookies passed to info + download — Me1)
INFO_JSON=$(yt-dlp -J --no-playlist "${COOKIES_ARGS[@]+"${COOKIES_ARGS[@]}"}" "$URL" 2>"$YTDLP_ERR")
YTDLP_INFO_RC=$?

if [ "$YTDLP_INFO_RC" -ne 0 ]; then
  ERR_MSG=$(head -5 "$YTDLP_ERR")
  if echo "$ERR_MSG" | grep -qi 'sign in\|bot\|429\|403\|auth'; then
    if [ "$USE_COOKIES" -eq 0 ]; then
      echo "NEEDS_COOKIES: ask the user, then re-run with --cookies" >&2
      exit 2
    fi
  fi
  echo "WARNING: yt-dlp info failed, trying FxTwitter direct-mp4 fallback" >&2
  YTDLP_FAILED=1
else
  SELECTOR=$(echo "$INFO_JSON" | python3 "$SCRIPT_DIR/pick-format.py" 2>/dev/null)
  if [ -z "$SELECTOR" ]; then
    SELECTOR="best[ext=mp4][height<=1080]/best"
  fi
  echo "INFO selector=$SELECTOR"

  yt-dlp --no-playlist -N 4 \
    -f "$SELECTOR" \
    --merge-output-format mp4 \
    --max-filesize "$MAX_FILESIZE" \
    -o "$OUT_TEMPLATE" \
    "${COOKIES_ARGS[@]+"${COOKIES_ARGS[@]}"}" \
    "$URL" 2>"$YTDLP_ERR"
  YTDLP_RC=$?

  if [ "$YTDLP_RC" -ne 0 ]; then
    echo "WARNING: yt-dlp download failed, trying FxTwitter direct-mp4 fallback" >&2
    YTDLP_FAILED=1
  else
    YTDLP_FAILED=0
  fi
fi

# --- Phase 2: FxTwitter direct-mp4 fallback ---
if [ "${YTDLP_FAILED:-1}" = "1" ]; then
  MP4_URL=$(echo "$STATUS_JSON" | jq -r \
    ".videos[$VID_IDX].formats | map(select(.container==\"mp4\")) | sort_by(.bitrate) | last | .url")

  if [ -z "$MP4_URL" ] || [ "$MP4_URL" = "null" ]; then
    echo "ERROR: no direct mp4 URL available (yt-dlp failed and FxTwitter has no mp4)" >&2
    if [ "$USE_COOKIES" -eq 0 ]; then
      echo "NEEDS_COOKIES: this may be a restricted tweet — re-run with --cookies" >&2
      exit 2
    fi
    exit 1
  fi

  echo "INFO fallback=fxmp4 url=${MP4_URL:0:80}..."
  CURL_MAX_SIZE=""
  if [ "$SIZE_CAP_BYTES" -gt 0 ] 2>/dev/null; then
    CURL_MAX_SIZE="--max-filesize $SIZE_CAP_BYTES"
  fi
  # shellcheck disable=SC2086
  curl -sL -A "Mozilla/5.0" $CURL_MAX_SIZE -o "${OUT_DIR}/${ID}.mp4" "$MP4_URL"
  CURL_RC=$?
  if [ "$CURL_RC" -ne 0 ]; then
    echo "ERROR: direct mp4 download failed (curl exit $CURL_RC)" >&2
    exit 1
  fi
fi

# --- Phase 3: ffprobe verify ---
OUT_FILE="${OUT_DIR}/${ID}.mp4"
if [ ! -f "$OUT_FILE" ]; then
  echo "ERROR: output file not found: $OUT_FILE" >&2
  exit 1
fi

FILE_SIZE=$(stat -f%z "$OUT_FILE" 2>/dev/null || stat -c%s "$OUT_FILE" 2>/dev/null)

# Enforce size cap deterministically (M2) — yt-dlp --max-filesize is unreliable for HLS
if [ "$SIZE_CAP_BYTES" -gt 0 ] 2>/dev/null && [ "$FILE_SIZE" -gt "$SIZE_CAP_BYTES" ] 2>/dev/null; then
  echo "ERROR: file size ${FILE_SIZE} bytes exceeds cap ${SIZE_CAP_BYTES} bytes (${MAX_FILESIZE})" >&2
  rm -f "$OUT_FILE"
  exit 7
fi

# Parse ffprobe output as JSON via jq (Mi4 — robust multi-stream parsing)
PROBE_JSON=$(ffprobe -hide_banner -v error \
  -show_entries format=duration,size,bit_rate \
  -show_entries stream=codec_type,codec_name,width,height \
  -of json "$OUT_FILE" 2>&1)
PROBE_RC=$?

if [ "$PROBE_RC" -ne 0 ]; then
  echo "ERROR: ffprobe verification failed" >&2
  echo "$PROBE_JSON" >&2
  exit 6
fi

DURATION=$(echo "$PROBE_JSON" | jq -r '.format.duration // empty')
V_CODEC=$(echo "$PROBE_JSON" | jq -r '[.streams[] | select(.codec_type=="video") | .codec_name] | .[0] // empty')
WIDTH=$(echo "$PROBE_JSON" | jq -r '[.streams[] | select(.codec_type=="video") | .width] | .[0] // empty')
HEIGHT=$(echo "$PROBE_JSON" | jq -r '[.streams[] | select(.codec_type=="video") | .height] | .[0] // empty')
A_CODEC=$(echo "$PROBE_JSON" | jq -r '[.streams[] | select(.codec_type=="audio") | .codec_name] | .[0] // empty')

if [ -z "$A_CODEC" ]; then
  A_CODEC="none"
fi

echo "VERIFY file=$OUT_FILE"
echo "VERIFY size=${FILE_SIZE} duration=${DURATION}s"
echo "VERIFY video=$V_CODEC ${WIDTH}x${HEIGHT}"
echo "VERIFY audio=$A_CODEC"
exit 0