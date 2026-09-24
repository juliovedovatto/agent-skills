#!/usr/bin/env node

import { YoutubeTranscript } from 'youtube-transcript-plus';

const videoArg = process.argv[2];

if (!videoArg) {
  console.error('Usage: transcript.js <video-id-or-url> [lang]');
  console.error('Example: transcript.js EBw7gsDPAYQ');
  console.error('Example: transcript.js https://www.youtube.com/watch?v=EBw7gsDPAYQ');
  console.error('Optional 2nd arg forces a language code, e.g. transcript.js EBw7gsDPAYQ pt-BR');
  process.exit(1);
}

// Extract video ID if full URL is provided
let extractedId = videoArg;
if (videoArg.includes('youtube.com') || videoArg.includes('youtu.be')) {
  const match = videoArg.match(/(?:v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
  if (match) {
    extractedId = match[1];
  }
}

// Optional language override as 2nd CLI arg
const langOverride = process.argv[3];

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/**
 * Resolve the video's ORIGINAL caption language (not a machine-translated track).
 *
 * YouTube now auto-generates ASR tracks in many languages (ar, bn, en, pt-BR, ...)
 * and `youtube-transcript-plus` picks tracks[0] — alphabetically first — when no
 * lang is passed, which is often a translated track, not the original.
 *
 * The Innertube player response marks the original: audioTracks[0] (the default
 * audio track) carries defaultCaptionTrackIndex pointing at the original-language
 * caption track. Falls back to the first manual (non-ASR) track.
 * Returns null when detection fails — caller then uses the library default.
 */
async function resolveOriginalLang(videoId) {
  try {
    const watchRes = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
      headers: { 'User-Agent': USER_AGENT },
    });
    if (!watchRes.ok) return null;
    const html = await watchRes.text();
    const apiKey = html.match(/"INNERTUBE_API_KEY":"([^"]+)"/)?.[1];
    if (!apiKey) return null;

    const playerRes = await fetch(
      `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'User-Agent': USER_AGENT },
        body: JSON.stringify({
          context: { client: { clientName: 'ANDROID', clientVersion: '20.10.38' } },
          videoId,
        }),
      }
    );
    if (!playerRes.ok) return null;
    const player = await playerRes.json();
    const tracklist =
      player.captions?.playerCaptionsTracklistRenderer ??
      player.playerCaptionsTracklistRenderer;
    const tracks = tracklist?.captionTracks ?? [];
    if (!Array.isArray(tracks) || tracks.length === 0) return null;

    // 1) Default audio track's defaultCaptionTrackIndex → original language
    const defaultIdx = tracklist.audioTracks?.[0]?.defaultCaptionTrackIndex;
    if (typeof defaultIdx === 'number' && tracks[defaultIdx]) {
      return tracks[defaultIdx].languageCode;
    }

    // 2) First manual (non-ASR) caption track
    const manual = tracks.find((t) => t.kind !== 'asr');
    return manual?.languageCode ?? null;
  } catch {
    return null;
  }
}

try {
  const lang = langOverride ?? (await resolveOriginalLang(extractedId));
  const transcript = await YoutubeTranscript.fetchTranscript(
    extractedId,
    lang ? { lang } : undefined
  );

  for (const entry of transcript) {
    const timestamp = formatTimestamp(entry.offset);
    console.log(`[${timestamp}] ${entry.text}`);
  }
} catch (error) {
  console.error('Error fetching transcript:', error.message);
  process.exit(1);
}

function formatTimestamp(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);

  if (h > 0) {
    return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }
  return `${m}:${s.toString().padStart(2, '0')}`;
}