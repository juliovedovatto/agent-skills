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
6. **Draft via `writer` subagent.** Pass: topic/summary, platform, confirmed language, desired length, and the User Writing Style below. Writer outputs in chat, never files.
7. **Present the draft.** Keep it short (3–5 short lines with line breaks). Max 4 hashtags, lowercase.
8. **Ask about images.** "Want carousel/images for this post?" Only invoke `social-media-images` if the user says yes.
9. **Scheduling with Buffer.** Before creating a Buffer post, decide the asset mode with this decision tree. A post uses EITHER images OR a link preview, never both — LinkedIn replaces the link card with image attachments, so attaching images suppresses the preview.

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
- Default language: ask the user to choose English or pt_BR before drafting, unless the current request explicitly specifies the language.
- Draft length: very short, 3–5 short lines with line breaks.
- Hashtags: max 4, all lowercase.
- No engagement bait.

## User Writing Style

When drafting LinkedIn text/headlines for this user, aim for:

- Direct, practical, developer-to-developer tone.
- Short paragraphs with generous spacing.
- Concept first, tool/solution second.
- Plain language over clever hooks.
- A simple takeaway at the end.
- Light use of “you”; avoid sounding accusatory.
- No hype, no viral framing, no engagement bait.

Preferred structure:

```text
[Clear technical statement].

[Practical implication / problem signal].

[Tool or solution, briefly explained].

[Short examples, if useful].

[Simple takeaway].
```

Avoid headline/post patterns like:

- “Stop doing X”
- “You’re using X wrong”
- “This changed everything”
- Overly dramatic hooks
- Generic calls for comments/reactions

Avoid repetitive takeaway formulas like:

- “Less X. Same Y.”
- “More X. Less Y.”
- “X, not Y.”
- Overly aphoristic one-liners

Prefer a natural final sentence that states the practical implication plainly.

Prefer headline styles like:

- “Better layering starts with boundaries”
- “z-index needs context”
- “Create stacking context on purpose”
- “Keep z-index local”
- “When z-index keeps growing, check the boundary”

Example tone:

```text
In CSS, z-index only competes inside the same stacking context.

If you keep changing z-index values to make layout interactions behave, you might have a stacking problem.

Tailwind's isolate utility creates a new stacking context on purpose.

Use it on component roots that manage internal layers:

→ modals
→ dropdowns
→ cards with badges
→ toasts

Better layering comes from boundaries, not bigger numbers.
```

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
