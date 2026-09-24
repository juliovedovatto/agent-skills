#!/usr/bin/env bash
set -u

# download.sh — YouTube video download with bot-check fallback.
# Exit codes: 0 ok | 2 needs-cookies (re-run with --cookies) | 1 other failure.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_ERR_FILE="/tmp/yt-dlp-info-err.$$"
STDERR_FILE="/tmp/yt-dlp-dl-err.$$"
trap 'rm -f "$INFO_ERR_FILE" "$STDERR_FILE"' EXIT

URL=""
OUT_DIR="${HOME}/tmp/.pi"
USE_COOKIES=0
POSITIONAL_COUNT=0

for arg in "$@"; do
  case "$arg" in
    --cookies) USE_COOKIES=1 ;;
    -h|--help)
      echo "Usage: download.sh <url> [output-dir] [--cookies]"
      exit 0 ;;
    *)
      POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
      if [ "$POSITIONAL_COUNT" -eq 1 ]; then
        URL="$arg"
      elif [ "$POSITIONAL_COUNT" -eq 2 ]; then
        OUT_DIR="$arg"
      else
        echo "ERROR: unexpected extra argument: $arg" >&2
        echo "Usage: download.sh <url> [output-dir] [--cookies]" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$URL" ]; then
  echo "ERROR: missing <url> argument" >&2
  echo "Usage: download.sh <url> [output-dir] [--cookies]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "ERROR: yt-dlp not found (brew install yt-dlp)" >&2
  exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ERROR: ffprobe not found (brew install ffmpeg)" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found (brew install python)" >&2
  exit 1
fi

COOKIES_ARGS=()
if [ "$USE_COOKIES" -eq 1 ]; then
  COOKIES_ARGS=(--cookies-from-browser chrome)
fi

# --- Phase 1: INFO (never cookies) ---
INFO_JSON=$(yt-dlp -J --no-playlist "$URL" 2>"$INFO_ERR_FILE")
INFO_RC=$?
if [ "$INFO_RC" -ne 0 ]; then
  echo "ERROR: yt-dlp info query failed:" >&2
  tail -n 15 "$INFO_ERR_FILE" >&2
  exit 1
fi

INFO_LINE=$(printf '%s' "$INFO_JSON" | python3 "$SCRIPT_DIR/pick-formats.py" 2>/dev/null)

if [ -z "$INFO_LINE" ]; then
  echo "ERROR: could not parse info JSON" >&2
  exit 1
fi

IFS='|' read -r VIDEO_ID VIDEO_FMT VIDEO_HEIGHT VIDEO_CODEC VIDEO_WIDTH VIDEO_REAL_HEIGHT AUDIO_FMT AUDIO_LANG NOTE_RAW AUDIO_WARN <<< "$INFO_LINE"

echo "INFO video_id=$VIDEO_ID"
echo "INFO video fmt=$VIDEO_FMT res=${VIDEO_HEIGHT}p w=$VIDEO_WIDTH h=$VIDEO_REAL_HEIGHT codec=$VIDEO_CODEC"
echo "INFO audio fmt=$AUDIO_FMT lang=$AUDIO_LANG note=$NOTE_RAW"
case "$VIDEO_CODEC" in
  *"+WARN:no-avc1"*) echo "WARNING: no avc1/mp4 video <=1080 — fell back to another codec." >&2 ;;
esac
if [ -n "$AUDIO_WARN" ]; then
  echo "WARNING: no 'original (default)' audio track found — auto-dub risk." >&2
fi

# --- Phase 2/3: DOWNLOAD ---
OUT_TEMPLATE="${OUT_DIR}/${VIDEO_ID}-${VIDEO_HEIGHT}p.%(ext)s"

run_download() {
  local selector="$1"
  yt-dlp --no-playlist -N 4 \
    -f "$selector" \
    --merge-output-format mp4 \
    -o "$OUT_TEMPLATE" \
    "${COOKIES_ARGS[@]+"${COOKIES_ARGS[@]}"}" \
    "$URL" 2>"$STDERR_FILE"
  return $?
}

BOT_RE='Sign in to confirm|\bbot\b|HTTP Error 429|HTTP Error 403|Too Many Requests'
FMT_RE='Requested format is not available'

if [ -z "$VIDEO_FMT" ]; then
  echo "ERROR: no video format <=1080p found" >&2
  exit 1
fi
SELECTOR="${VIDEO_FMT}+${AUDIO_FMT}"
if [ -z "$AUDIO_FMT" ]; then
  SELECTOR="$VIDEO_FMT"
  echo "WARNING: no audio format pinned — video-only download." >&2
fi

run_download "$SELECTOR"
DL_RC=$?

if [ "$DL_RC" -ne 0 ]; then
  STDERR_TAIL=$(tail -n 15 "$STDERR_FILE")

  if echo "$STDERR_TAIL" | grep -Eqi "$BOT_RE"; then
    if [ "$USE_COOKIES" -eq 0 ]; then
      echo "NEEDS_COOKIES: ask the user, then re-run with --cookies"
      exit 2
    else
      echo "ERROR: bot-check persists even with cookies:" >&2
      echo "$STDERR_TAIL" >&2
      exit 1
    fi
  fi

  if echo "$STDERR_TAIL" | grep -Eqi "$FMT_RE"; then
    echo "WARNING: explicit format IDs unavailable — selector retry." >&2
    FALLBACK="bv[vcodec^=avc][ext=mp4][width<=1920][height<=1920]+ba"
    if [ "$USE_COOKIES" -eq 1 ]; then
      echo "WARNING: audio track unpinned under cookies — may be a YouTube dub; verify language before posting." >&2
    else
      echo "WARNING: audio unpinned (dub risk)." >&2
    fi
    run_download "$FALLBACK"
    DL_RC=$?
    if [ "$DL_RC" -ne 0 ]; then
      STDERR_TAIL=$(tail -n 15 "$STDERR_FILE")
      if echo "$STDERR_TAIL" | grep -Eqi "$BOT_RE" && [ "$USE_COOKIES" -eq 0 ]; then
        echo "NEEDS_COOKIES: ask the user, then re-run with --cookies"
        exit 2
      fi
      echo "ERROR: download failed:" >&2
      echo "$STDERR_TAIL" >&2
      exit 1
    fi
  else
    echo "ERROR: download failed:" >&2
    echo "$STDERR_TAIL" >&2
    exit 1
  fi
fi

# --- Phase 4: VERIFY ---
DOWNLOADED_FILE="${OUT_DIR}/${VIDEO_ID}-${VIDEO_HEIGHT}p.mp4"
if [ ! -f "$DOWNLOADED_FILE" ]; then
  echo "ERROR: output file not found after download: $DOWNLOADED_FILE" >&2
  exit 1
fi

PROBE=$(ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,codec_type,width,height \
  -of default=noprint_wrappers=1 "$DOWNLOADED_FILE" 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "ERROR: ffprobe failed on $DOWNLOADED_FILE" >&2
  exit 1
fi

DURATION=$(echo "$PROBE" | grep '^duration=' | cut -d= -f2)
SIZE_BYTES=$(echo "$PROBE" | grep '^size=' | cut -d= -f2)
# codec_name precedes codec_type in ffprobe output — track the last seen.
V_CODEC=$(echo "$PROBE" | awk -F= '/codec_name=/{last=$2} /codec_type=video/{print last}' | head -n1)
A_CODEC=$(echo "$PROBE" | awk -F= '/codec_name=/{last=$2} /codec_type=audio/{print last}' | head -n1)
WIDTH=$(echo "$PROBE" | grep '^width=' | cut -d= -f2)
HEIGHT=$(echo "$PROBE" | grep '^height=' | cut -d= -f2)

SIZE_MB=$(python3 -c "print(f'{(${SIZE_BYTES:-0}/1048576):.1f}')" 2>/dev/null || echo "?")
DUR_S=$(python3 -c "print(f'{float(\"${DURATION:-0}\"):.1f}')" 2>/dev/null || echo "?")

echo "VERIFY file=${DOWNLOADED_FILE}"
echo "VERIFY size=${SIZE_MB}MB duration=${DUR_S}s"
echo "VERIFY video=${V_CODEC} ${WIDTH}x${HEIGHT}"
echo "VERIFY audio=${A_CODEC}"

echo "OK $(cd "$(dirname "$DOWNLOADED_FILE")" && pwd)/$(basename "$DOWNLOADED_FILE")"