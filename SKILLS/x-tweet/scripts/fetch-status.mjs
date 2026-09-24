#!/usr/bin/env node
// fetch-status.mjs — syndication-primary + fxtwitter-enrichment → ONE normalized JSON on stdout.
// Exit codes: 0 ok (JSON on stdout) | 3 tombstone/deleted | 4 transient 5xx/rate-limit | 5 ok-but-no-media

const SYNDICATION_UA = 'Googlebot';
const FXTWITTER_UA = 'Mozilla/5.0 (compatible; Pi-skill/x-tweet)';

function syndicationToken(id) {
  return ((Number(id) / 1e15) * Math.PI).toString(36).replace(/[0.]/g, '');
}

async function fetchJson(url, ua) {
  const r = await fetch(url, { headers: { 'User-Agent': ua }, signal: AbortSignal.timeout(15000) });
  const status = r.status;
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status, json, text };
}

function die(code, msg) {
  process.stderr.write(`fetch-status: ${msg}\n`);
  process.exit(code);
}

async function main() {
  const input = process.argv[2] ?? '';
  if (!input) { die(2, 'missing URL argument'); }

  // Normalize the input to a tweet ID
  let norm;
  try {
    const { execSync } = await import('node:child_process');
    const scriptDir = new URL('.', import.meta.url).pathname;
    const out = execSync(`node "${scriptDir}normalize-url.mjs" '${input.replace(/'/g, "'\\''")}'`, { encoding: 'utf8' });
    norm = JSON.parse(out);
  } catch (e) {
    die(2, `could not normalize URL: ${e.message}`);
  }

  const id = norm.id;
  const mediaIndex = norm.mediaIndex;
  const mediaKind = norm.mediaKind;

  // --- Phase 1: syndication (primary — text, author, media) ---
  const token = syndicationToken(id);
  const syn = await fetchJson(
    `https://cdn.syndication.twimg.com/tweet-result?id=${id}&token=${token}`,
    SYNDICATION_UA
  );

  let synd = null;
  if (syn.status === 200 && syn.json) {
    synd = syn.json;
  } else if (syn.status >= 500 || syn.status === 429) {
    die(4, `syndication transient error: HTTP ${syn.status}`);
  }
  // If syndication 404 or empty, fall through to FxTwitter

  // --- Phase 2: FxTwitter (enrichment — counts, avatar, quote, media formats) ---
  const fx = await fetchJson(`https://api.fxtwitter.com/2/status/${id}`, FXTWITTER_UA);

  if (fx.status === 404 || (fx.json && fx.json.code === 404)) {
    die(3, `tweet not found or deleted (id=${id})`);
  }
  if (fx.status >= 500 || fx.status === 429) {
    die(4, `FxTwitter transient error: HTTP ${fx.status}`);
  }
  if (fx.json && fx.json.status && fx.json.status.type === 'tombstone') {
    die(3, `tweet unavailable: ${fx.json.status.reason || 'tombstone'}`);
  }

  const fxStatus = fx.json?.status ?? null;

  // If BOTH sources failed, we can't produce data
  if (!synd && !fxStatus) {
    die(4, `both syndication and FxTwitter returned no data for id=${id}`);
  }

  // --- Merge into a normalized shape ---
  // Prefer syndication for text/author (first-party), FxTwitter for enrichment.
  const sUser = synd?.user;
  const fxAuthor = fxStatus?.author;
  const fxMedia = fxStatus?.media;

  // Photos: from syndication mediaDetails (type=photo) or FxTwitter media.photos
  const photos = [];
  const syndMedia = synd?.mediaDetails || [];
  for (const m of syndMedia) {
    if (m.type === 'photo') {
      photos.push({
        url: m.media_url_https,
        width: m.original_info?.width || 0,
        height: m.original_info?.height || 0,
      });
    }
  }
  if (photos.length === 0 && fxMedia?.photos) {
    for (const p of fxMedia.photos) {
      photos.push({ url: p.url, width: p.width || 0, height: p.height || 0 });
    }
  }

  // Videos: from syndication video.variants or FxTwitter media.videos[].formats
  const videos = [];
  for (const m of syndMedia) {
    if (m.type === 'video' || m.type === 'animated_gif') {
      const variants = (m.video_info?.variants || [])
        .filter(v => v.content_type === 'video/mp4')
        .map(v => ({ container: 'mp4', bitrate: v.bitrate || 0, url: v.url }));
      videos.push({
        poster: m.media_url_https,
        type: m.type === 'animated_gif' ? 'gif' : 'video',
        durationMs: m.video_info?.duration_millis || 0,
        formats: variants,
      });
    }
  }
  if (videos.length === 0 && fxMedia?.videos) {
    for (const v of fxMedia.videos) {
      videos.push({
        poster: v.thumbnail_url || null,
        type: v.type === 'gif' ? 'gif' : 'video',
        durationMs: v.duration || 0,
        formats: (v.formats || [])
          .filter(f => f.container === 'mp4')
          .map(f => ({ container: 'mp4', bitrate: f.bitrate || 0, url: f.url })),
      });
    }
  }

  // Poll from FxTwitter (top-level status.poll, choices[].{label,count})
  const poll = fxStatus?.poll ? {
    endsAt: fxStatus.poll.ends_at || null,
    options: (fxStatus.poll.choices || []).map(c => ({ label: c.label, votes: c.count || 0 })),
  } : null;

  // Quoted tweet (from FxTwitter — singular `quote` object, not `quotes` count)
  const fxQuote = fxStatus?.quote;
  const quoted = fxQuote ? {
    author: fxQuote.author?.screen_name || '',
    text: fxQuote.text || (fxQuote.type === 'tombstone' ? (fxQuote.reason || 'unavailable') : ''),
  } : null;

  // Retweet unwrap (from FxTwitter — reposted_by is an object, extract screen_name)
  const retweeter = fxStatus?.reposted_by?.screen_name ?? null;

  // Reply context (replying_to is an object with screen_name and status)
  const replyTo = fxStatus?.replying_to ? {
    id: fxStatus.replying_to.status ?? null,
    screenName: fxStatus.replying_to.screen_name ?? null,
  } : null;

  const result = {
    id,
    canonical: `https://x.com/i/status/${id}`,
    mediaIndex,
    mediaKind,
    author: {
      name: sUser?.name || fxAuthor?.name || '',
      screenName: sUser?.screen_name || fxAuthor?.screen_name || '',
      avatar: sUser?.profile_image_url_https || fxAuthor?.avatar_url || '',
    },
    text: synd?.text || fxStatus?.text || '',
    createdAt: synd?.created_at || fxStatus?.created_at || '',
    lang: synd?.lang || fxStatus?.lang || '',
    source: fxStatus?.source || '',
    counts: {
      replies: fxStatus?.replies ?? synd?.conversation_count ?? null,
      reposts: fxStatus?.reposts ?? null,
      likes: fxStatus?.likes ?? synd?.favorite_count ?? null,
      bookmarks: fxStatus?.bookmarks ?? null,
      views: fxStatus?.views ?? null,
    },
    photos,
    videos,
    poll,
    quoted,
    retweeter,
    replyTo,
    sources: { syndication: !!synd, fxtwitter: !!fxStatus },
  };

  // exit 5 = media-less status; callers decide (screenshots OK, downloads fail)
  if (videos.length === 0 && photos.length === 0 && !poll) {
    process.stdout.write(JSON.stringify(result));
    process.stderr.write(`fetch-status: tweet has no media (id=${id})\n`);
    process.exitCode = 5;
    return;
  }

  process.stdout.write(JSON.stringify(result));
}

main().catch(e => die(4, `unexpected error: ${e.message}`));