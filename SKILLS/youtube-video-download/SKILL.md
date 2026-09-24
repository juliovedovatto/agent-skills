---
name: youtube-video-download
description: >
  Download a YouTube video or Short as a clean MP4 (H.264/AAC, ≤1080p) with
  yt-dlp, verify the result with ffprobe, and recover from YouTube bot-check
  blocks and format-ID drift by retrying with Chrome cookies. Use when asked to
  download a YouTube video, save a Short for re-uploading or attaching to a
  social post (Buffer/LinkedIn video limits), check a video's codec,
  resolution, duration, or size, or when yt-dlp fails with "Sign in to confirm
  you're not a bot" or "Requested format is not available".
---

# YouTube Video Download

Download YouTube videos/Shorts as MP4 (H.264/AAC, ≤1080p) with yt-dlp,
verify with ffprobe, and recover from bot-checks. Optimized for social-media
attachment use (LinkedIn/Buffer: MP4, H.264/AAC).

## Prerequisites

- `yt-dlp` and `ffmpeg` via Homebrew. If yt-dlp is stale, run `brew upgrade
  yt-dlp` FIRST — `yt-dlp -U` errors on Homebrew installs.
- Chrome logged into YouTube on this machine (needed only for the cookie
  fallback).

## Workflow

### 1. Run the script

```bash
bash <skill-dir>/scripts/download.sh "<video-url>"
```

Resolve `<skill-dir>` relative to this SKILL.md file: `scripts/download.sh`
sits one level below the skill root. Default output directory is `~/tmp/.pi/`
(created automatically). Pass a second arg to override the output directory.

The script runs in four phases: INFO (queries formats, no cookies), DOWNLOAD
(no cookies first), COOKIES retry (only when re-run with `--cookies`), and
VERIFY (ffprobe). It pins the H.264/≤1080p video format and the
`original (default)` audio track automatically.

### 2. Read the summary output

The script prints an INFO summary (video id, chosen video format + height +
codec, chosen audio format + language + note) and a VERIFY summary:

```
VERIFY file=/Users/.../VIDEO_ID-1080p.mp4
VERIFY size=8.2MB duration=42.0s
VERIFY video=h264 1080x1920
VERIFY audio=aac
```

Report codec, resolution, duration, and size to the user. Check against the
target platform's limits (e.g. LinkedIn: MP4, H.264/AAC, ≥75KB, ≤5GB).

### 3. If it exits with NEEDS_COOKIES

The script exits with code 2 and prints:

```
NEEDS_COOKIES: ask the user, then re-run with --cookies
```

ASK THE USER FIRST — macOS keychain may prompt for their Chrome password.
Only after consent, re-run:

```bash
bash <skill-dir>/scripts/download.sh "<video-url>" --cookies
```

NEVER pass cookies to info/queries — the script already isolates cookies to
the download call only, which is why the keychain prompt (if any) happens
during the download step only.

### 4. Manual fallback (only if the script itself is broken)

1. `yt-dlp -F "<url>"` (and again with `--cookies-from-browser chrome` if the
   plain listing bot-blocks) — format IDs drift between player APIs, so pick
   IDs from the listing that matches your cookie state.
2. Choose the H.264 (`avc1`) video format ≤1080p and the m4a audio whose note
   contains `original` — that is the `original (default)` track. Suffixed
   IDs (`140-0`, `140-20`, …) are auto-dubs; the `original` one is the real
   audio.
3. `yt-dlp -f "<video-id>+<audio-id>" --merge-output-format mp4 -o "<dir>/<name>.%(ext)s" "<url>"`
4. `rm` any stale partial file before retrying.
5. Verify with the ffprobe recipe above.

## Gotchas

- **Format IDs drift under cookies.** Without cookies yt-dlp uses the plain
  player API; with cookies it can switch to the creator-player API where
  dubbed audio tracks get suffixed IDs. The script pins the original track in
  the no-cookie path; the cookie selector fallback (`bv+ba`) is the residual
  dub risk — verify the audio language before posting.
- **Stale yt-dlp.** Run `brew upgrade yt-dlp` first — `yt-dlp -U` errors on
  Homebrew installs.
- **Stale partial files.** `rm` before re-downloading, then ffprobe the new
  file.
- **Playlists.** The script passes `--no-playlist`; manual fallback should
  too.
- **Re-encoding for social platforms.** When a re-encode is needed (e.g. the
  file is too large for a hoster's upload limit), always add
  `-movflags +faststart` — without it the `moov` atom sits at the end of the
  MP4 and platform extractors that range-read the file fail (Buffer's video
  thumbnail step returns `422 {"error":"No frame data extracted"}`;
  verified 2026-09-23). The script's merged output already has faststart.
  Also note hoster-side caps: the Cloudinary MCP upload base64s local files,
  so the source file must stay under ~47 MB — see the `social-media-post`
  skill for the video-attachment pipeline.

## Out of scope

Audio-only downloads, thumbnail extraction, subtitle files — for transcripts
use the `youtube-transcript` skill.