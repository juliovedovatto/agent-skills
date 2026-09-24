#!/usr/bin/env node
// normalize-url.mjs — any tweet URL form → JSON {id, mediaIndex, canonical}
// Handles: x.com/<u>/status/<id>, twitter.com/..., x.com/i/status/<id>,
//          x.com/i/web/status/<id>, mobile.twitter.com/..., t.co/<short>,
//          bare numeric IDs, /video/N and /photo/N index suffixes.
// Exit codes: 0 ok | 2 unrecognized/malformed

import { execFileSync } from 'node:child_process';

function bail(msg) {
  process.stderr.write(`normalize-url: ${msg}\n`);
  process.exit(2);
}

function expandTco(url) {
  try {
    return execFileSync('curl', ['-sL', '-o', '/dev/null', '-w', '%{url_effective}', '-A', 'Mozilla/5.0', url], {
      encoding: 'utf8', timeout: 15000,
    }).trim();
  } catch {
    bail(`could not resolve t.co shortlink: ${url}`);
  }
}

function normalizeId(raw) {
  const id = raw.replace(/^0+/, '');
  if (!id || !/^\d+$/.test(id)) bail(`invalid tweet ID: ${raw}`);
  return id;
}

function parse(input) {
  const s = String(input).trim();

  // Bare numeric ID
  if (/^\d+$/.test(s)) {
    const id = normalizeId(s);
    return { id, mediaKind: null, mediaIndex: null, canonical: `https://x.com/i/status/${id}` };
  }

  // t.co shortlink — expand then recurse
  if (/^https?:\/\/t\.co\//i.test(s)) {
    const expanded = expandTco(s);
    return parse(expanded);
  }

  // x.com / twitter.com / mobile.twitter.com URL — host-restricted
  if (/^https?:\/\//i.test(s)) {
    let parsed;
    try {
      parsed = new URL(s);
    } catch {
      bail(`malformed URL: ${s}`);
    }
    const host = parsed.hostname.toLowerCase();
    if (host !== 'x.com' && host !== 'twitter.com' && host !== 'mobile.twitter.com') {
      bail(`not a twitter/x.com URL: ${s}`);
    }
    const m = parsed.pathname.match(
      /^\/(?:[^/]+|i\/web|i)\/status(?:es)?\/(\d+)(?:\/(video|photo)\/(\d+))?$/i
    );
    if (m) {
      const id = normalizeId(m[1]);
      const mediaKind = m[2] || null;
      const mediaIndex = m[3] ? parseInt(m[3], 10) : null;
      return { id, mediaKind, mediaIndex, canonical: `https://x.com/i/status/${id}` };
    }
    bail(`unrecognized tweet URL path: ${s}`);
  }

  bail(`unrecognized tweet URL or ID: ${s}`);
}

const out = parse(process.argv[2] ?? '');
process.stdout.write(JSON.stringify(out));