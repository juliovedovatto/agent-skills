#!/usr/bin/env node
// render-card.mjs — inline data URLs, build self-contained HTML, screenshot via
// playwright-core + system Chrome (element crop, auto height) → ~/tmp/.pi/<id>.png
// Usage: render-card.mjs <url-or-id> [output-dir]

import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { mkdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const PW_PATH = '/Users/juliovedovatto/.pi/agent/npm/node_modules/playwright-core';
const SYSTEM_CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SCRIPT_DIR = new URL('.', import.meta.url).pathname;

function die(code, msg) {
  process.stderr.write(`render-card: ${msg}\n`);
  process.exit(code);
}

async function fetchAsDataUrl(url) {
  if (!url) { return null; }
  try {
    const r = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Pi-skill/x-tweet)' },
      signal: AbortSignal.timeout(15000),
    });
    if (!r.ok) { return null; }
    const buf = new Uint8Array(await r.arrayBuffer());
    const ct = r.headers.get('content-type') || 'image/jpeg';
    const b64 = Buffer.from(buf).toString('base64');
    return `data:${ct};base64,${b64}`;
  } catch {
    return null;
  }
}

function escHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function main() {
  const input = process.argv[2] ?? '';
  if (!input) { die(2, 'missing URL argument'); }
  const outDir = process.argv[3] || join(homedir(), 'tmp', '.pi');
  mkdirSync(outDir, { recursive: true });

  // fetch-status exits 5 for no-media tweets — fine for screenshots (text-only card).
  let status;
  try {
    const { spawnSync } = await import('node:child_process');
    const res = spawnSync('node', [`${SCRIPT_DIR}fetch-status.mjs`, input], {
      encoding: 'utf8', timeout: 30000,
    });
    const exitCode = res.status ?? 1;
    if (exitCode === 2 || exitCode === 3 || exitCode === 4) {
      die(exitCode, `fetch-status exited ${exitCode}: ${res.stderr?.trim() || ''}`);
    }
    if (!res.stdout?.trim()) {
      die(1, `fetch-status produced no output: ${res.stderr?.trim() || ''}`);
    }
    status = JSON.parse(res.stdout.trim());
  } catch (e) {
    if (e.code && typeof e.code === 'number') { die(e.code, e.message); }
    die(1, `fetch-status failed: ${e.message}`);
  }

  const id = status.id;
  const outFile = join(outDir, `${id}.png`);

  // Inline all remote images as data URLs
  const [avatarData, ...photoData] = await Promise.all([
    fetchAsDataUrl(status.author.avatar),
    ...(status.photos || []).map(p => fetchAsDataUrl(p.url)),
  ]);

  // Video poster frames — inline the poster image
  const posterData = await Promise.all(
    (status.videos || []).map(v => fetchAsDataUrl(v.poster))
  );

  // Build self-contained HTML
  const cardWidth = 580;
  let html = `<!doctype html><html><head><meta charset="utf-8">
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  :root{color-scheme:light dark;--fg:#0f172a;--bg:#fff;--rule:#e2e8f0;--muted:#64748b;--accent:#475569}
  @media(prefers-color-scheme:dark){:root{--fg:#e2e8f0;--bg:#0f172a;--rule:#334155;--muted:#94a3b8;--accent:#94a3b8}}
  body{padding:24px;background:var(--bg);font:16px/1.5 -apple-system,system-ui,sans-serif;width:${cardWidth + 48}px}
  .card{border:1px solid var(--rule);border-radius:12px;padding:20px;width:${cardWidth}px}
  .retweeter{font-size:13px;color:var(--muted);margin-bottom:12px}
  .author{display:flex;gap:12px;align-items:center;margin-bottom:14px}
  .avatar{width:48px;height:48px;border-radius:999px;flex-shrink:0}
  .name{font-weight:600;color:var(--fg)}
  .handle{color:var(--muted);font-size:14px}
  .text{color:var(--fg);white-space:pre-wrap;word-wrap:break-word;margin-bottom:14px;dir:auto}
  .media-grid{display:grid;gap:8px;margin-bottom:14px}
  .media-grid.single{grid-template-columns:1fr}
  .media-grid.two{grid-template-columns:1fr 1fr}
  .media-grid.three{grid-template-columns:1fr 1fr 1fr}
  .media-grid.four{grid-template-columns:1fr 1fr}
  .media-item{border-radius:8px;overflow:hidden}
  .media-item img{width:100%;display:block}
  .video-poster{position:relative;border-radius:8px;overflow:hidden;margin-bottom:14px}
  .video-poster img{width:100%;display:block}
  .video-poster .play{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
    width:56px;height:56px;
    display:flex;align-items:center;justify-content:center;
    border-radius:999px;background:rgba(0,0,0,0.7);
    color:#fff;font-size:24px}
  .gif-badge{position:absolute;top:8px;right:8px;
    padding:2px 8px;
    border-radius:4px;background:rgba(0,0,0,0.7);
    color:#fff;font-size:12px}
  .poll{margin-bottom:14px}
  .poll-option{margin-bottom:8px}
  .poll-label{font-size:14px;color:var(--fg);margin-bottom:2px}
  .poll-bar{height:8px;border-radius:4px;background:var(--rule)}
  .poll-fill{height:8px;border-radius:4px;background:var(--accent)}
  .poll-pct{font-size:13px;color:var(--muted)}
  .quoted{border:1px solid var(--rule);border-radius:8px;padding:12px;margin-bottom:14px}
  .quoted-author{font-size:14px;color:var(--muted);margin-bottom:4px}
  .quoted-text{font-size:15px;color:var(--fg);white-space:pre-wrap;word-wrap:break-word;dir:auto}
  .reply-context{font-size:13px;color:var(--muted);margin-bottom:8px}
  .counts{display:flex;gap:18px;color:var(--muted);font-size:13px;margin-bottom:8px}
  .meta{font-size:13px;color:var(--muted)}
</style></head><body><div class="card">`;

  // Retweet notice
  if (status.retweeter) {
    html += `<div class="retweeter">${escHtml(status.retweeter)} reposted</div>`;
  }

  // Reply context
  if (status.replyTo) {
    const replyLabel = status.replyTo.screenName
      ? `Replying to @${escHtml(status.replyTo.screenName)}`
      : 'Replying to a previous post';
    html += `<div class="reply-context">${replyLabel}</div>`;
  }

  // Author
  html += `<div class="author">`;
  if (avatarData) {
    html += `<img class="avatar" src="${avatarData}">`;
  } else {
    html += `<div class="avatar" style="background:var(--rule)"></div>`;
  }
  html += `<div><div class="name">${escHtml(status.author.name)}</div>` +
    `<div class="handle">@${escHtml(status.author.screenName)}</div></div></div>`;

  // Text (dir="auto" for RTL)
  if (status.text) {
    html += `<div class="text" dir="auto">${escHtml(status.text)}</div>`;
  }

  // Quoted tweet
  if (status.quoted) {
    html += `<div class="quoted">`;
    html += `<div class="quoted-author">@${escHtml(status.quoted.author)}</div>`;
    html += `<div class="quoted-text" dir="auto">${escHtml(status.quoted.text)}</div>`;
    html += `</div>`;
  }

  // Photos
  const photos = photoData.filter(Boolean);
  if (photos.length > 0) {
    const cls = photos.length === 1 ? 'single' : photos.length === 2 ? 'two' :
      photos.length === 3 ? 'three' : 'four';
    html += `<div class="media-grid ${cls}">`;
    for (const p of photos) {
      html += `<div class="media-item"><img src="${p}"></div>`;
    }
    html += `</div>`;
  }

  // Video poster frames — iterate unfiltered pairs so GIF badges align correctly (Mi9)
  for (let i = 0; i < posterData.length; i++) {
    const pd = posterData[i];
    if (!pd) { continue; }
    const v = status.videos[i];
    html += `<div class="video-poster">`;
    html += `<img src="${pd}">`;
    if (v?.type === 'gif') {
      html += `<div class="gif-badge">GIF</div>`;
    }
    html += `<div class="play">▶</div></div>`;
  }

  // Poll
  if (status.poll && status.poll.options?.length > 0) {
    const total = status.poll.options.reduce((s, o) => s + (o.votes || 0), 0);
    html += `<div class="poll">`;
    for (const opt of status.poll.options) {
      const pct = total > 0 ? Math.round((opt.votes / total) * 100) : 0;
      html += `<div class="poll-option">`;
      html += `<div class="poll-label">${escHtml(opt.label)}</div>`;
      html += `<div class="poll-bar"><div class="poll-fill" style="width:${pct}%"></div></div>`;
      html += `<div class="poll-pct">${pct}%</div>`;
      html += `</div>`;
    }
    html += `</div>`;
  }

  // Counts
  const c = status.counts;
  const countsHtml = [];
  if (c.replies != null) { countsHtml.push(`${c.replies} replies`); }
  if (c.reposts != null) { countsHtml.push(`${c.reposts} reposts`); }
  if (c.likes != null) { countsHtml.push(`${c.likes} likes`); }
  if (c.bookmarks != null) { countsHtml.push(`${c.bookmarks} bookmarks`); }
  if (c.views != null) { countsHtml.push(`${c.views} views`); }
  if (countsHtml.length > 0) {
    html += `<div class="counts">${countsHtml.map((t) => `<span>${escHtml(t)}</span>`).join('')}</div>`;
  }

  // Meta
  if (status.createdAt) {
    const created = new Date(status.createdAt);
    const createdLabel = Number.isNaN(created.getTime())
      ? status.createdAt
      : created.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    html += `<div class="meta">${escHtml(createdLabel)}`;
    if (status.source) { html += ` · ${escHtml(status.source)}`; }
    html += `</div>`;
  }

  html += `</div></body></html>`;

  // Screenshot via playwright-core + system Chrome
  let chromium;
  try {
    chromium = require(PW_PATH).chromium;
  } catch {
    die(1, `playwright-core not found at ${PW_PATH}`);
  }

  let browser;
  try {
    browser = await chromium.launch({ headless: true, executablePath: SYSTEM_CHROME });
  } catch (e) {
    die(1, `could not launch Chrome: ${e.message}`);
  }

  try {
    const page = await browser.newPage({ viewport: { width: cardWidth + 48, height: 800 } });
    await page.setContent(html, { waitUntil: 'load' });
    const card = await page.locator('.card');
    await card.screenshot({ path: outFile });
    await browser.close();
  } catch (e) {
    await browser.close().catch(() => {});
    die(1, `screenshot failed: ${e.message}`);
  }

  // Report
  const size = require('node:fs').statSync(outFile).size;
  process.stdout.write(`SHOT file=${outFile}\n`);
  process.stdout.write(`SHOT size=${size} id=${id}\n`);
}

main().catch(e => die(1, `unexpected: ${e.message}`));