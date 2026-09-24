---
name: x-tweet
description: >
  Screenshot a tweet/X post as a PNG and/or download a video from it. Use when
  asked to screenshot an X/Twitter post, capture a tweet as an image, download
  a Twitter/X video, save a tweet video as MP4, grab a tweet's media, or get a
  tweet's text and engagement counts as a rendered card. Also triggers on
  "tweet screenshot", "X post image", "save tweet video", "download X video".
---

# x-tweet

Screenshot X/Twitter posts as PNG cards and download tweet videos as MP4.
No API key, no browser login. Uses X's syndication endpoint (primary metadata),
FxTwitter (enrichment/fallback), yt-dlp (video primary), and headless Chrome
(screenshot). Output goes to `~/tmp/.pi/`.

## Prerequisites

```bash
bash <skill-dir>/scripts/probe-env.sh
```

Requires: `yt-dlp`, `ffmpeg`/`ffprobe`, `jq`, `curl`, `python3`, `node`, and
system Chrome at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`.
If yt-dlp is stale, run `brew upgrade yt-dlp` first (`yt-dlp -U` errors on
Homebrew installs).

## Workflow

### Screenshot a tweet

```bash
bash <skill-dir>/scripts/x-tweet.sh shot "https://x.com/jack/status/20"
```

Outputs `~/tmp/.pi/<id>.png`. Pass a second arg to override the output dir.

The script fetches tweet metadata (syndication primary, FxTwitter enrichment),
renders a self-contained HTML card with all images inlined as data URLs, and
screenshots it via `playwright-core` + system Chrome (element-level crop, auto
height). Video tweets render their poster frame (not a live `<video>`).

If `playwright-core` is unavailable, use the Chrome CLI fallback (full-window
capture, not an element crop — the output will be larger than the primary
path's tight card screenshot):

```bash
bash <skill-dir>/scripts/screenshot-chrome.sh "https://x.com/jack/status/20"
```

### Download a video

```bash
bash <skill-dir>/scripts/x-tweet.sh video "https://x.com/NASA/status/2102748685792596449"
```

Outputs `~/tmp/.pi/<id>.mp4`, verified with `ffprobe`. Pass a second arg to
override the output dir. Default size cap is 500 MB; override with
`--max-filesize 100M`. The cap is enforced after download: if the output
exceeds the cap, the file is deleted and the script exits with code 7.

The script tries yt-dlp first (best video ≤1080p + best audio via
`pick-format.py`, merged into a single mp4 with both tracks). If yt-dlp fails,
it falls back to FxTwitter's highest-bitrate direct mp4 URL. Media URLs are
always re-fetched immediately before download (they expire in ~7 days).

### Cookie fallback (consent-gated)

If the video script exits with code 2 (`NEEDS_COOKIES`), the tweet may be
age-restricted or the author may have limited the audience. Only after explicit
user consent, re-run with `--cookies`:

```bash
bash <skill-dir>/scripts/x-tweet.sh video "<url>" --cookies
```

The script prints a one-line notice before using cookies. Cookies are passed
to the yt-dlp info and download calls only; never used for
syndication/FxTwitter metadata fetches.

## Reading the output

Screenshot prints:

```
SHOT file=/Users/.../tmp/.pi/20.png
SHOT size=24576 id=20
```

Video download prints:

```
VERIFY file=/Users/.../tmp/.pi/2102748685792596449.mp4
VERIFY size=8495403 duration=30.08s
VERIFY video=h264 1920x1080
VERIFY audio=aac
```

If the download has no audio track, `audio=none` is reported honestly.

Check codec, resolution, duration, and size against your target platform's
limits.

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Other failure |
| 2    | Malformed URL, or needs cookies (re-run with `--cookies`) |
| 3    | Tweet deleted or unavailable (tombstone) |
| 4    | Transient server error (5xx/rate-limit) — try again later |
| 5    | Tweet has no video to download                                   |
| 6    | ffprobe verification failed (corrupt output)                     |
| 7    | File exceeds the `--max-filesize` cap (file deleted)             |

## Known limitations

- **Old amplify tweets.** yt-dlp's `amp.twimg.com` step 500s on very old
  tweets. The FxTwitter direct-mp4 fallback covers this, but if the tweet is
  old enough the CDN URL may also 404.
- **NSFW/age-restricted tweets.** Require `--cookies` after logging into x.com
  in Chrome and viewing the post while logged in.
- **Multi-video tweets.** Use `/video/N` in the URL to select a specific video
  (e.g. `…/status/123/video/2`). Default is the first video.
- **No media URLs persisted.** The script never stores mp4 URLs or raw status
  JSON to disk — always re-fetches immediately before download. Temp files
  (yt-dlp stderr, screenshot HTML) are written under `~/tmp/.pi/.x-tweet-tmp/`
  and cleaned up on exit; a SIGKILL may leave litter there.
- **Personal use.** Downloaded video and photos are copyrightable media. This
  is a local personal tool for capturing individual public posts. Respect
  authors, do not strip watermarks, do not mass-archive, do not download
  premium/paid content.

## Out of scope

- Bulk tweet scraping or archiving.
- Downloading DMs or private/protected accounts (requires auth, out of scope).
- Live x.com page screenshots (the login wall and hydration delay make this
  unreliable; the self-rendered card is deterministic and offline-capable).
- Audio-only extraction from tweets (use yt-dlp directly if needed).