---
name: video-audio-transcription
description: Extract text/transcription from local video and audio files. Use when the user asks to transcribe, caption, or extract spoken text from a local media file. Transcribes locally with a Whisper backend (mlx_whisper by default on macOS).
---

# video-audio-transcription

Extract spoken text from local video or audio files.

## Failure Policy

Follow only the documented method.

If it fails, stop. Do not retry failed steps with different arguments, search for alternatives, install tools, call other APIs, write ad-hoc scripts, or ask the user to brainstorm workarounds.

Report:
1. every method attempted
2. the exact error or deterministic failure message for each one
3. the next explicit action the user can approve, if any

Continue only after explicit user approval.

## Workflow

1. **Local Whisper backend — macOS default**
   Run:
   ```bash
   scripts/local-whisper-transcribe.sh <video-or-audio-path> [language]
   ```
   - Default language: `pt`
   - Exit codes:
     - `0`: success
     - `1`: error (file not found, ffmpeg missing, backend not found, model download not approved, whisper.cpp model path missing)
   - Deterministic messages:
     - `NO_WHISPER_BACKEND`: no local backend found
     - `WHISPER_MODEL_DOWNLOAD_APPROVAL_REQUIRED`: backend found but auto-download is blocked
     - `WHISPER_CPP_MODEL_PATH_REQUIRED`: whisper.cpp found but `WHISPER_CPP_MODEL` is not set

   - On macOS the default backend is `mlx_whisper`. When it is missing, ask the user to approve `uv tool install mlx-whisper`; the first run also downloads the model (~1.6 GB) and needs `VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1`.
## Audio extraction helper

Some backends need a normalized audio file. Use:
```bash
scripts/extract-audio.sh <video-or-audio-path> [output.wav]
```
Defaults to writing `~/tmp/.pi/<basename>.wav` (mono, 16 kHz, WAV).
- On failure, prints the path to the ffmpeg error log under `~/tmp/.pi/`.

## Environment variables

- macOS: `mlx_whisper` auto-downloads its model on first run. Approve it with:
  ```bash
  export VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1
  ```
- Linux: `whisper-cli` (whisper.cpp) needs a local model already on disk:
  ```bash
  export WHISPER_CPP_MODEL=/path/to/ggml-model.bin
  ```
- The `mlx_whisper` backend pins `mlx-community/whisper-large-v3-turbo` by default,
  because mlx_whisper's own default (`tiny`) is too weak to be useful. Override with
  `WHISPER_MLX_MODEL`:
  ```bash
  export WHISPER_MLX_MODEL=mlx-community/whisper-large-v3
  ```

## Validation

```bash
# 1. Check scripts exist and are executable
ls -la scripts/

# 2. Check bash script usage (no args)
scripts/local-whisper-transcribe.sh
# Expected: prints usage, exits 1

# 3. Check bash script missing file
scripts/local-whisper-transcribe.sh /nonexistent/file.mp4
# Expected: ERROR: Input file not found, exits 1

# 4. Check extract-audio.sh usage (no args)
scripts/extract-audio.sh
# Expected: prints usage, exits 1
```
