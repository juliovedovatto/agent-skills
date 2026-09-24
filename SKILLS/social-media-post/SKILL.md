---
name: social-media-post
description: |
  Create concise social media post drafts from ideas, YouTube videos, research,
  questions, or rough notes. Content-first — invokes social-media-images
  only when carousel/image assets are requested.
---

# Social Media Post

Generate social media post drafts from source material.

## When to use

- "Write a LinkedIn post about…"
- "Turn this YouTube video into a post"
- "Research this and make a social post"
- "Polish my draft"

Use this skill first; only invoke `social-media-images` for carousel/image generation.

## Workflow

1. **Clarify source and intent.** What is the source? What kind of post? (share a take, explain a concept, promote something, summarize.)
2. **YouTube source?** Fetch transcript via the `youtube-transcript` skill first. Summarize key points before drafting.
3. **Facts needed?** Research before drafting. Present findings briefly if the topic is unfamiliar to the user.
4. **Identify angles.** Pick 1–3 possible angles. If none is obviously best, ask the user to choose.
5. **Confirm language.** Before invoking `writer`, ask whether the post should be in English or pt_BR unless the user already specified the language in the current request.
6. **Draft via `writer` subagent.** Pass: topic/summary, platform, confirmed language, desired length, and the User Writing Style below. For source-sharing posts (video/article), the brief MUST also name the CHOSEN ANGLE — the ONE thing the user liked — plus the source-sharing directive from the Short reaction post rules below. Never pass a full multi-item summary of the source without a chosen angle: given an enumeration, the writer enumerates. Writer outputs in chat, never files. If subagents are available, check for a `writer` agent. If it exists, ask the user whether to use it or the `writers-room` skill (a council of multiple model voices composed into one draft) instead.
   - `writer` available + `writers-room` available → ask the user which they want.
   - only `writer` available → use it.
   - neither available → compose inline. Inline is an exception, never a default.
   - **Voice corpus is MANDATORY for both agents — PASS the file:** when dispatching `writer`, or when invoking `writers-room` and composing its drafts, the brief MUST include the corpus `references/writing-style-database.csv` (absolute path resolved against this skill's directory) and state as the FIRST instruction that the agent must read that file and derive the voice from those real posts BEFORE drafting; if the receiving agent cannot read files, inline the CSV contents in the brief instead of a path. The corpus is the only ground truth for tone, sentence shapes, openings, closings, and hashtag habits — a draft written from the style summary alone was rejected by the user as off-voice.
   - **Orwell rule (mandatory):** composing the text MUST go through the `orwell-writing` skill whenever it is available. Load it for inline composition, and instruct a delegated `writer` subagent to apply Orwell's six rules and ASD-STE100 as part of its brief. Do not draft final prose without it.
7. **Present the draft.** Keep it short (3–5 short lines with line breaks). Max 4 hashtags, lowercase.
8. **Ask about images.** "Want carousel/images for this post?" Only invoke `social-media-images` if the user says yes.
9. **Scheduling with Buffer.** Before creating a Buffer post, decide the asset mode with this decision tree. A post uses EITHER images OR a link preview, never both — LinkedIn replaces the link card with image attachments, so attaching images suppresses the preview.

   **Step 0 — Does the post share a video?**
   - **Yes → video mode.** The video replaces the link card; strip any URL from the post text and attach NO link preview:
     - Source the MP4 via the `youtube-video-download` skill (H.264 + AAC, vertical or landscape)
     - Host it on Cloudinary under `linkedin/posts/{post-alias}/` (same folder pattern as images)
     - **Cloudinary MCP upload size cap:** the MCP base64s local files, so the file must stay under ~47 MB (62,910,000-char data-URI limit; a 50 MB video becomes a ~70 MB URI and is rejected). Larger → re-encode first (see flag below), then upload
     - **`-movflags +faststart` is MANDATORY on every re-encode:** without it the MP4's `moov` atom sits at the end of the file and Buffer's thumbnail extractor fails with `422 {"error":"No frame data extracted"}` (verified 2026-09-23). yt-dlp merge output already has faststart; hand-run ffmpeg does not. Also normalize the frame rate for fragment-merge sources: yt-dlp output can declare `r_frame_rate=60/1` while averaging 30, and Cloudinary mirrors the wrong value — add `-profile:v high -fps_mode cfr -r 30`
       ```
       ffmpeg -i in.mp4 -c:v libx264 -crf 26 -preset medium -c:a copy -movflags +faststart out.mp4
       ```
     - **Buffer asset shape (create):** `assets: [{ video: { url, metadata: { thumbnailOffset: <ms>, title } } }]` — flat/other shapes are rejected
     - **buffer_edit_post video quirk:** the edit validation may reject the video metadata wrapper; retry with the minimal `{ video: { url } }` — title/thumbnailOffset are dropped (Buffer falls back to its default frame)
     - **Always verify the thumbnail:** fetch the post's returned `thumbnail` URL. `200 image/jpeg` is NOT sufficient — a flat placeholder passes it. Assert real content: ≥0.02 bytes/pixel (verified real frames 0.033–0.043; the placeholder is 0.006). On `422`, re-upload with faststart under a NEW Cloudinary public_id (a new source URL forces thumbnail regeneration), swap the asset via edit, and re-verify
     - **Black/blank thumbnail → trim the head and retry:** a constant flat placeholder (identical bytes across different source URLs, ~0.006 bytes/pixel, drawn at the video's own dimensions) means the extractor failed on the video's head — waiting never fixes it, and changing `thumbnailOffset` alone never fixes it either. Re-encode with `-ss 0.5` (0.5 s off the start), re-upload under a NEW public_id, swap via edit, and re-check. If still flat, trim further (1 s, 1.5 s, …) until the thumbnail is a real picture. Verified: 0.5 s turned a 0.006 bytes/pixel placeholder into a real 0.043 frame. Trimming shifts the timeline — subtract the trim from `thumbnailOffset` so the poster still lands on the intended moment — and eye-check the returned image, since a non-flat frame can still be the wrong moment

   **Step 1 — Does the post have attached images?**
   - **Yes → image mode.** Skip the link preview entirely, even if the text contains a URL:
     - Host the final images on Cloudinary before creating the Buffer post
     - Use the folder pattern `linkedin/posts/{post-alias}/`, where `{post-alias}` is a short kebab-case alias confirmed by the user or safely derived from the post topic
     - Pass the returned Cloudinary image URLs to Buffer as post assets (type `image`)
     - **Also record the Cloudinary URLs in a Buffer post Note:** After creating the Buffer post, add a Note to that post whose `text` is a raw JSON array of the Cloudinary delivery URLs, in the order the images are attached/sent in the post — e.g. `["https://res.cloudinary.com/dvkfw97zt/image/upload/.../img1.png","https://res.cloudinary.com/dvkfw97zt/image/upload/.../img2.png"]`. The portfolio site reads `Post.notes[].text` to recover permanent image URLs, because LinkedIn CDN URLs expire (~3 weeks after publish) and Buffer's API does not re-sign them. Add the note via the Buffer web UI during scheduling — Buffer's API has no mutation to create notes.

   **Step 2 — No images. Does the post text contain a URL?**
   - **Yes → link-preview mode (automatic).** Do this automatically whenever there are no attached images and the text contains a URL. Do NOT rely on a bare URL in the text to produce a preview on its own — explicitly attach the link so the card renders reliably:
     - Run `scripts/og-scraper.sh <URL>` to extract Open Graph metadata
     - Use the returned JSON in the `assets[]` array:
       ```javascript
       assets: [{
         link: {
           url: "...",
           title: "...",
           description: "...",
           thumbnailUrl: "..."
         }
       }]
       ```
     - Buffer will populate `metadata.linkAttachment` automatically from the assets
     - This generates the LinkedIn preview card (title, description, thumbnail)
   - **No URL and no images → text-only post.** No assets.

## Defaults

- Default platform: LinkedIn.
- Default scheduling: one post every 2 days at 09:00 America/Sao_Paulo (12:00 UTC); if the next date lands on a Saturday/Sunday, move it to the next Monday. First free slot after the last already-scheduled post. When the user says "schedule it" without a date, use Buffer `customScheduled` with `dueAt` `YYYY-MM-DDT09:00:00-03:00` — never Buffer's automatic slot. Cadence updated 2026-09-23 (every 2 days + weekend rule, owner directive); supersedes the 2026-08-29 Mon/Wed/Fri rule (which existed because an automatic slot landed on a Sunday morning).
- Default language: ask the user to choose English or pt_BR before drafting, unless the current request explicitly specifies the language.
- Draft length: match the post type — short reaction (~270–600 chars, 2–4 sentences) or long-form reflective (1–2 dense paragraphs of 4–8 sentences). Default to short unless the user asks to explain or opine.
- Hashtags: max 4, all lowercase.
- No engagement bait.

## User Writing Style

**Reference corpus:** `references/writing-style-database.csv` (`date,text` columns). Load it when learning or verifying this user's voice — it is the ground truth for tone, length, structure, and hashtag habits. The guidance below is derived from it.

**Personal file — generate it if missing:** the corpus is never shipped with this skill, so check for it before drafting and build it when absent: list the channel's published posts with the Buffer MCP (`list_posts`, `status: ["sent"]`, paging with `next_cursor`), and write one row per post — `date` = the full `sentAt` ISO timestamp, `text` = the post body RFC-4180 quoted (bodies contain newlines, commas and quotes), under a `date,text` header. Never invent posts and never substitute a generic style guide for the real corpus; if it cannot be generated, say so and ask the user before drafting.

When drafting LinkedIn text/headlines for this user, aim for:

- Direct, practical, developer-to-developer tone.
- Concept first, tool/solution second.
- Plain language over clever hooks.
- A simple takeaway in the middle, not at the end — a closing takeaway reads as AI filler. Close on the short examples.
- Light use of “you”; avoid sounding accusatory.
- No hype, no viral framing, no engagement bait.

### Prose structure

The user's real posts are **personal reactions to a source**, not textbook primers. Lead with a first-person take, point to the link, keep it casual. Do not write an explanatory essay that replaces the source. Apply the rules below by post type.

**Short reaction post (default — sharing a video, article, or trick):** one flowing block of 2–4 joined sentences. No chunking, but do NOT pad to 4+ sentences. Land ~270–600 chars. End on the source link.

When the post shares a video/article (source-sharing):

- Do NOT enumerate or narrate the source's contents. Do not survey its features.
- Lead with a short direct verdict on the release/topic, then a first-person reaction to ONE thing you liked (the chosen angle).
- Describe the liked thing by benefit in your own words, not a mechanism recap (no API/property name-dropping unless the user wrote it).
- No meta-sentence like "the video covers the rest" — the link carries the rest.

**Long-form reflective post (explaining a concept or an opinion essay):** now apply the dense-paragraph rules:
- **Semantic unity:** a paragraph is one block of thought. Break ONLY on a distinct new subtopic or major argument.
- **Density:** 4–8 interconnected sentences per paragraph. No single- or two-sentence paragraphs.
- **Internal flow:** connect ideas with transition phrases (consequently, furthermore, in contrast) instead of new line breaks.

**Both modes:**
- **No artificial line breaks:** join related sentences; do not put every sentence on its own line. Break only for a structural shift (before a `→` list, a source link, the hashtag line, or a real topic change).
- **No visual chunking:** no bullet points, bolded lead-ins, or mid-topic spacing unless explicitly requested.
- Personal, first-person voice ("I think…", "Here's a trick…", "This is one of those features I didn't know I wanted"). Light emoji mid-text is on-brand. Hashtags lowercase, max 4.

## Tools

### og-scraper.sh

Extract Open Graph metadata from a URL or raw HTML for Buffer link previews. Backed by `og-scraper.py` (uses the `metadata-parser` PyPI library) and run through `uv`, so **no `curl`/`wget`** is used (those are hook-blocked in this environment).

**Location:** `scripts/og-scraper.sh` + `scripts/og-scraper.py`

**Usage:**
```bash
# URL mode — fetch and extract
./scripts/og-scraper.sh <URL>

# HTML mode — parse raw HTML from a file (no network fetch)
./scripts/og-scraper.sh --html <FILE>

# HTML mode — parse raw HTML from stdin
cat page.html | ./scripts/og-scraper.sh --html -
```

**Output (stdout only, compact JSON):**
```json
{
  "url": "https://example.com",
  "title": "Page Title",
  "description": "Page description",
  "thumbnailUrl": "https://example.com/image.jpg"
}
```

**Requirements:**
- `uv` (provides `uv run --with metadata-parser`)
- Python 3.12
- No `curl`/`wget`/`jq` — the Python library handles fetching and parsing

**When to use:**
- Before creating Buffer posts via MCP that contain URLs (URL mode)
- When you already have the page HTML (e.g. fetched via `ctx_fetch_and_index` or `fetch_content`) and want to avoid a second network call (HTML mode)
- To generate LinkedIn link preview cards automatically
- Falls back to `<title>` and meta description if OG tags are missing; on fetch/parse failure, emits a valid JSON object with empty string fields (never a traceback on stdout)

**Note:** The library parses real HTML, so it handles pages where the `<meta>` attribute order is reversed (e.g. `content="..." property="og:title"`), which a naive regex would miss.

## Skill Boundary

- `social-media-post` owns caption/body text and idea development.
- `social-media-images` owns visual assets and image-overlay text.

## Skill requirements

- **Video posts** — `yt-dlp` + `ffmpeg`: source the MP4 with the `youtube-video-download` skill, then re-encode with `ffmpeg` (video mode carries the mandatory faststart and frame-rate flags).
- **Cloudinary MCP** — hosts the images and the video under `linkedin/posts/{post-alias}/`.
- **Buffer MCP** — creates and schedules the post.
- **Link previews** — the og-scraper's own requirements are listed under `## Tools`.
