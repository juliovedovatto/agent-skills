#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: extract-audio.sh <video-or-audio-path> [output.wav]"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

input="$1"
if [ ! -f "$input" ]; then
    echo "ERROR: Input file not found: $input"
    exit 1
fi

if [ $# -ge 2 ]; then
    output="$2"
else
    base=$(basename "$input")
    base="${base%.*}"
    mkdir -p "$HOME/tmp/.pi"
    output="$HOME/tmp/.pi/${base}.wav"
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ERROR: ffmpeg not found in PATH"
    exit 1
fi

mkdir -p "$HOME/tmp/.pi"
ffmpeg_log="$HOME/tmp/.pi/ffmpeg-audio-extract-$(date +%s).log"

if ! ffmpeg -y -i "$input" -vn -acodec pcm_s16le -ac 1 -ar 16000 "$output" 2>"$ffmpeg_log"; then
    echo "ERROR: ffmpeg failed to extract audio. See log: $ffmpeg_log"
    exit 1
fi

echo "$output"
