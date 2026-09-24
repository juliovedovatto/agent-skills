#!/usr/bin/env bash
set -u

# x-tweet.sh — entrypoint for the x-tweet skill.
# Usage:
#   x-tweet.sh shot <url> [output-dir]   — screenshot a tweet
#   x-tweet.sh video <url> [output-dir] [--cookies] [--max-filesize <size>]  — download video
#   x-tweet.sh probe                      — check prerequisites
# Exit codes mirror the underlying scripts:
#   0 ok | 1 other | 2 malformed/needs-cookies | 3 tombstone/deleted | 4 transient | 5 no-media | 6 ffprobe-fail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-}"

usage() {
  cat <<'EOF'
Usage: x-tweet.sh <command> [args]
  shot <url> [output-dir]          Screenshot a tweet as PNG
  video <url> [output-dir] [opts]  Download tweet video as MP4
    --cookies                      Use Chrome cookies (consent-gated)
    --max-filesize <size>          Size cap (default 500M)
  probe                            Check prerequisites
EOF
}

case "$CMD" in
  shot)
    shift
    node "$SCRIPT_DIR/render-card.mjs" "$@" || exit $?
    ;;
  video)
    shift
    bash "$SCRIPT_DIR/download-video.sh" "$@" || exit $?
    ;;
  probe)
    bash "$SCRIPT_DIR/probe-env.sh" || exit $?
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown command '$CMD'" >&2
    usage
    exit 1
    ;;
esac