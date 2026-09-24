---
name: youtube-transcript
description: Fetch transcripts from YouTube videos for summarization and analysis.
---

# YouTube Transcript

Fetch transcripts from YouTube videos.

## Setup

```bash
cd {baseDir}
npm install
```

## Usage

```bash
{baseDir}/transcript.js <video-id-or-url>
```

Accepts video ID or full URL:
- `EBw7gsDPAYQ`
- `https://www.youtube.com/watch?v=EBw7gsDPAYQ`
- `https://youtu.be/EBw7gsDPAYQ`

Optional 2nd arg forces a language code (e.g. `transcript.js EBw7gsDPAYQ pt-BR`).

## Output

Timestamped transcript entries:

```
[0:00] All right. So, I got this UniFi Theta
[0:15] I took the camera out, painted it
[1:23] And here's the final result
```

## Notes

- Requires the video to have captions/transcripts available
- Works with auto-generated and manual transcripts
- **Defaults to the video's ORIGINAL language.** YouTube auto-generates ASR tracks in many languages (ar, bn, en, pt-BR, …) and `youtube-transcript-plus` picks the first one (alphabetical) when no `lang` is passed — often a machine-translated track. The script resolves the original via the Innertube player response (`audioTracks[0].defaultCaptionTrackIndex`, fallback: first manual/non-ASR track) and passes it to the library. Detection failure falls back to the library default. Pass a 2nd arg to force a language.
