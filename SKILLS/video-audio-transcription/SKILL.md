---
name: video-audio-transcription
description: Extract text/transcription from local video and audio files. Use when the user asks to transcribe, caption, or extract spoken text from a local media file. Falls back from Gemini video analysis to macOS Speech to local Whisper backends.
---

# video-audio-transcription

Extract spoken text from local video or audio files.

## Failure Policy

Follow only the documented fallback order.

If the primary method and all applicable fallbacks fail, stop. Do not retry failed steps with different arguments, search for alternatives, install tools, call other APIs, write ad-hoc scripts, or ask the user to brainstorm workarounds.

Report:
1. every method attempted
2. the exact error or deterministic failure message for each one
3. the next explicit action the user can approve, if any

Continue only after explicit user approval.

## Fallback Order

Use this order strictly:

1. `fetch_content` video analysis
2. `macos-speech-transcribe.swift`
3. `local-whisper-transcribe.sh`

`extract-audio.sh` is only a helper for documented backends. It is not an independent fallback.

If all applicable steps fail, stop and report the failure.

## Workflow

1. **Gemini video analysis**
   Try Pi `fetch_content` with the video file path and a transcription prompt. This requires Gemini access (cookie or API key). If it succeeds, return the result.

2. **macOS Speech**
   If step 1 fails, and the machine is macOS with Speech recognition authorized, run:
   ```bash
   scripts/macos-speech-transcribe.swift <video-or-audio-path> [locale] [timeout-seconds]
   ```
   - Default locale: `pt_BR`
   - Default timeout: `180` seconds
   - Exit codes:
     - `0`: success, transcript printed between `TRANSCRIPT_BEGIN` and `TRANSCRIPT_END`
     - `1`: error (not authorized, recognizer unavailable, timeout, file not found)
   - If the requested locale is unavailable, the script prints a `WARNING:` and falls back to the default recognizer.

3. **Local Whisper backend**
   If step 2 fails or is unavailable, run:
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

## Audio extraction helper

Some backends need a normalized audio file. Use:
```bash
scripts/extract-audio.sh <video-or-audio-path> [output.wav]
```
Defaults to writing `~/tmp/.pi/<basename>.wav` (mono, 16 kHz, WAV).
- On failure, prints the path to the ffmpeg error log under `~/tmp/.pi/`.

## Environment variables

- To allow model downloads for auto-download backends (`faster-whisper`, `whisper`, `mlx_whisper`), set:
  ```bash
  export VIDEO_TRANSCRIPTION_ALLOW_MODEL_DOWNLOAD=1
  ```
- For whisper.cpp backends (`whisper-cli`, `main`), set a local model path:
  ```bash
  export WHISPER_CPP_MODEL=/path/to/ggml-model.bin
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

# 4. Check swift typecheck
swift -typecheck scripts/macos-speech-transcribe.swift
# Expected: no output on success

# 5. Check swift executable bit
[[ -x scripts/macos-speech-transcribe.swift ]] && echo "executable" || echo "not executable"
# Expected: executable

# 6. Check extract-audio.sh usage (no args)
scripts/extract-audio.sh
# Expected: prints usage, exits 1
```
