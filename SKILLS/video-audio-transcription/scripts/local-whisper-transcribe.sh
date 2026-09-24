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

# One backend per platform: mlx_whisper on macOS (Metal-accelerated; install with
# `uv tool install mlx-whisper`), whisper-cli on Linux (whisper.cpp). faster-whisper
# and openai-whisper are deliberately absent: faster-whisper ships no executable,
# and openai-whisper is CPU-only and worse than mlx on the same audio.
if [ "$(uname -s)" == "Darwin" ]; then
    backends=("mlx_whisper")
else
    backends=("whisper-cli")
fi
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
    if [ "$(uname -s)" == "Darwin" ]; then
        echo "On macOS the default backend is mlx_whisper. Ask the user to approve installing it:"
        echo "  uv tool install mlx-whisper"
        echo "The first run also downloads the ${WHISPER_MLX_MODEL:-mlx-community/whisper-large-v3-turbo} model (~1.6 GB), which needs VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1."
    else
        echo "On Linux the backend is whisper-cli (whisper.cpp). Install it and point WHISPER_CPP_MODEL at a ggml model:"
        echo "  export WHISPER_CPP_MODEL=/path/to/ggml-model.bin"
    fi
    echo "Ask the user for approval before installing or downloading models."
    exit 1
fi

echo "Using backend: $chosen"

# Prevent silent model downloads.
# Backends that auto-download models: mlx_whisper
if [[ "$chosen" == "mlx_whisper" ]]; then
    if [ "${VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD:-}" != "1" ]; then
        echo "WHISPER_MODEL_DOWNLOAD_APPROVAL_REQUIRED"
        echo "Backend '$chosen' may auto-download models on first run."
        echo "Set VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1 to allow, or ask the user for approval."
        exit 1
    fi
fi

case "$chosen" in
    mlx_whisper)
        # mlx_whisper defaults to the tiny model — always pin an explicit one.
        "$chosen" "$audio_input" --model "${WHISPER_MLX_MODEL:-mlx-community/whisper-large-v3-turbo}" --language "$lang"
        ;;
    whisper-cli)
        if [ -n "${WHISPER_CPP_MODEL:-}" ]; then
            "$chosen" -m "$WHISPER_CPP_MODEL" -f "$audio_input"
        else
            echo "WHISPER_CPP_MODEL_PATH_REQUIRED"
            echo "Backend '$chosen' requires a local model path via WHISPER_CPP_MODEL environment variable."
            echo "Example: WHISPER_CPP_MODEL=/path/to/ggml-model.bin $chosen -f <audio>"
            exit 1
        fi
        ;;
esac
