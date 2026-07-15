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
9. **Scheduling with Buffer + LinkedIn images.** If the user wants to schedule the LinkedIn post through Buffer and the post has images, host the final images on Cloudinary before creating the Buffer post. Use the folder pattern `linkedin/posts/{post-alias}/`, where `{post-alias}` is a short kebab-case alias confirmed by the user or safely derived from the post topic. Pass the returned Cloudinary image URLs to Buffer as post assets.

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

## Skill Boundary

- `social-media-post` owns caption/body text and idea development.
- `social-media-images` owns visual assets and image-overlay text.
