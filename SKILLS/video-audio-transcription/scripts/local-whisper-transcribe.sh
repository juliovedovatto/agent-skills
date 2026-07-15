#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: local-whisper-transcribe.sh <video-or-audio-path> [language]"
    echo "  language: ISO 639-1 code (default: pt)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

input="$1"
lang="${2:-pt}"

if [ ! -f "$input" ]; then
    echo "ERROR: Input file not found: $input"
    exit 1
fi

# Determine audio input (extract if video)
audio_input="$input"
mime=$(file -b --mime-type "$input" 2>/dev/null || echo "unknown")
if [[ "$mime" == video/* ]]; then
    base=$(basename "$input")
    base="${base%.*}"
    mkdir -p "$HOME/tmp/.pi"
    audio_input="$HOME/tmp/.pi/${base}.wav"
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "ERROR: ffmpeg required for video input but not found"
        exit 1
    fi
    ffmpeg -y -i "$input" -vn -acodec pcm_s16le -ac 1 -ar 16000 "$audio_input" 2>/dev/null || true
fi

# Detect backends in priority order
backends=("faster-whisper" "whisper" "mlx_whisper" "whisper-cli" "main")
chosen=""
for backend in "${backends[@]}"; do
    if command -v "$backend" >/dev/null 2>&1; then
        chosen="$backend"
        break
    fi
done

if [ -z "${chosen}" ]; then
    echo "NO_WHISPER_BACKEND"
    echo "No local Whisper backend found. Available backends checked: ${backends[*]}"
    echo "Ask the user for approval before installing or downloading models."
    exit 1
fi

echo "Using backend: $chosen"

# Prevent silent model downloads.
# Backends that auto-download models: faster-whisper, whisper, mlx_whisper
if [[ "$chosen" == "faster-whisper" || "$chosen" == "whisper" || "$chosen" == "mlx_whisper" ]]; then
    if [ "${VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD:-}" != "1" ]; then
        echo "WHISPER_MODEL_DOWNLOAD_APPROVAL_REQUIRED"
        echo "Backend '$chosen' may auto-download models on first run."
        echo "Set VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1 to allow, or ask the user for approval."
        exit 1
    fi
fi

case "$chosen" in
    faster-whisper)
        if ! "$chosen" "$audio_input" --model small --language "$lang" 2>/dev/null; then
            "$chosen" "$audio_input" --model small
        fi
        ;;
    whisper)
        "$chosen" "$audio_input" --language "$lang" --model small
        ;;
    mlx_whisper)
        "$chosen" "$audio_input"
        ;;
    whisper-cli|main)
        if [ -n "${WHISPER_CPP_MODEL:-}" ]; then
            "$chosen" -m "$WHISPER_CPP_MODEL" -f "$audio_input"
        else
            echo "WHISPER_CPP_MODEL_PATH_REQUIRED"
            echo "Backend '$chosen' requires a local model path via WHISPER_CPP_MODEL environment variable."
            echo "Example: WHISPER_CPP_MODEL=/path/to/ggml-model.bin $chosen -f <audio>"
            exit 1
        fi
        ;;
    *)
        "$chosen" "$audio_input"
        ;;
esac
