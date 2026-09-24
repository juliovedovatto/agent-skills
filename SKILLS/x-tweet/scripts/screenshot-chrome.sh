#!/usr/bin/env bash
set -u

# screenshot-chrome.sh — Chrome CLI fallback for screenshots.
# Usage: screenshot-chrome.sh <url-or-id> [output-dir]
# Produces a full-window capture (not an element crop like the primary playwright path).
# Output dimensions will be larger than the primary path's tight card crop.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT_DIR="${HOME}/tmp/.pi"
URL="${1:-}"

if [ -z "$URL" ]; then
  echo "ERROR: missing URL argument" >&2
  echo "Usage: screenshot-chrome.sh <url-or-id> [output-dir]" >&2
  exit 2
fi
if [ "$#" -ge 2 ]; then
  OUT_DIR="$2"
fi
mkdir -p "$OUT_DIR"

# Get normalized tweet ID
NORM=$(node "$SCRIPT_DIR/normalize-url.mjs" "$URL" 2>/dev/null) || {
  echo "ERROR: could not normalize URL" >&2
  exit 2
}
ID=$(echo "$NORM" | jq -r '.id')

# Fetch status JSON and build a self-contained HTML temp file.
STATUS_JSON=$(node "$SCRIPT_DIR/fetch-status.mjs" "$URL" 2>/dev/null)
FETCH_RC=$?
if [ "$FETCH_RC" -ne 0 ] && [ "$FETCH_RC" -ne 5 ]; then
  echo "ERROR: fetch-status failed (exit $FETCH_RC)" >&2
  exit $FETCH_RC
fi
if [ -z "$STATUS_JSON" ]; then
  echo "ERROR: fetch-status produced no output" >&2
  exit 1
fi

TMP_DIR="${HOME}/tmp/.pi/.x-tweet-tmp"
mkdir -p "$TMP_DIR"
HTML_FILE="${TMP_DIR}/card-${ID}.html"
trap 'rm -f "$HTML_FILE"' EXIT

# Build HTML via a small node inline script (inline data URLs for determinism)
node -e "
const fs = require('fs');
const data = JSON.parse(process.argv[1]);
const id = data.id;
const outDir = process.argv[2];
(async () => {
  async function dl(url) {
    if (!url) { return null; }
    try {
      const r = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: AbortSignal.timeout(15000) });
      if (!r.ok) { return null; }
      const buf = new Uint8Array(await r.arrayBuffer());
      const ct = r.headers.get('content-type') || 'image/jpeg';
      return 'data:' + ct + ';base64,' + Buffer.from(buf).toString('base64');
    } catch { return null; }
  }
  const esc = s => String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;');
  const [avatar, ...photos] = await Promise.all([
    dl(data.author.avatar),
    ...(data.photos||[]).map(p => dl(p.url)),
  ]);
  const posters = await Promise.all((data.videos||[]).map(v => dl(v.poster)));
  let h = '<!doctype html><html><head><meta charset=\"utf-8\"><style>' +
    ':root{--fg:#0f172a;--bg:#fff;--rule:#e2e8f0;--muted:#64748b}' +
    '@media(prefers-color-scheme:dark){:root{--fg:#e2e8f0;--bg:#0f172a;--rule:#334155;--muted:#94a3b8}}' +
    'body{margin:0;padding:24px;background:var(--bg);font:16px/1.5 -apple-system,system-ui,sans-serif;width:628px}' +
    '.card{border:1px solid var(--rule);border-radius:12px;padding:20px;width:580px}' +
    '.author{display:flex;gap:12px;align-items:center;margin-bottom:14px}' +
    '.avatar{width:48px;height:48px;border-radius:999px;flex-shrink:0}' +
    '.name{font-weight:600;color:var(--fg)}.handle{color:var(--muted);font-size:14px}' +
    '.text{color:var(--fg);white-space:pre-wrap;word-wrap:break-word;margin-bottom:14px;dir:auto}' +
    '.media-item{border-radius:8px;overflow:hidden;margin-bottom:14px}.media-item img{width:100%;display:block}' +
    '.video-poster{position:relative;border-radius:8px;overflow:hidden;margin-bottom:14px}' +
    '.video-poster img{width:100%;display:block}' +
    '.counts{display:flex;gap:18px;color:var(--muted);font-size:13px;margin-bottom:8px}' +
    '.meta{font-size:13px;color:var(--muted)}' +
    '</style></head><body><div class=\"card\">';
  if (avatar) { h += '<div class=\"author\"><img class=\"avatar\" src=\"'+avatar+'\"><div><div class=\"name\">'+esc(data.author.name)+'</div><div class=\"handle\">@'+esc(data.author.screenName)+'</div></div></div>'; }
  if (data.text) { h += '<div class=\"text\" dir=\"auto\">'+esc(data.text)+'</div>'; }
  for (const p of photos.filter(Boolean)) { h += '<div class=\"media-item\"><img src=\"'+p+'\"></div>'; }
  for (let i=0;i<posters.length;i++){const pd=posters[i];if(!pd){continue;}h+='<div class=\"video-poster\"><img src=\"'+pd+'\"><div style=\"position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:56px;height:56px;border-radius:999px;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;color:#fff;font-size:24px\">▶</div></div>';}
  const c=data.counts;let ch=[];if(c.replies!=null){ch.push(c.replies+' replies');}if(c.reposts!=null){ch.push(c.reposts+' reposts');}if(c.likes!=null){ch.push(c.likes+' likes');}if(c.views!=null){ch.push(c.views+' views');}
  if(ch.length){h+='<div class=\"counts\">'+ch.map(esc).join('')+'</div>';}
  if(data.createdAt){h+='<div class=\"meta\">'+esc(data.createdAt)+'</div>';}
  h+='</div></body></html>';
  fs.writeFileSync(process.argv[3], h);
})();
" "$STATUS_JSON" "$OUT_DIR" "$HTML_FILE"

# Full-window capture — the fallback does not measure or clip to the card element.
# The primary playwright path (render-card.mjs) produces a tight element crop;
# this fallback captures the full 628px-wide window at a generous height.
WIDTH=628
HEIGHT=2000

OUT_FILE="${OUT_DIR}/${ID}.png"

rm -f "$OUT_FILE"

"$CHROME" --headless=new --disable-gpu --no-sandbox \
  --screenshot="$OUT_FILE" \
  --window-size="${WIDTH},${HEIGHT}" \
  --hide-scrollbars \
  --default-background-color=00000000 \
  "file://${HTML_FILE}" 2>/dev/null

rm -f "$HTML_FILE"

if [ -f "$OUT_FILE" ]; then
  SIZE=$(stat -f%z "$OUT_FILE" 2>/dev/null || stat -c%s "$OUT_FILE" 2>/dev/null)
  echo "SHOT file=${OUT_FILE}"
  echo "SHOT size=${SIZE} id=${ID}"
  exit 0
else
  echo "ERROR: Chrome CLI screenshot failed — no output file" >&2
  exit 1
fi