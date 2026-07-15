---
name: social-media-images
description: |
  Create consistent social media images and carousel assets for posts.
  Use when the user asks to create, plan, or generate images for LinkedIn or other social platforms.
  Supports reusable visual themes and an optional template/reference-image workflow for consistency.
compatibility: Uses the generate-image skill and Replicate. Requires REPLICATE_API_TOKEN when generating images.
---

# Social Media Images

Create social media images for posts, with a focus on consistent carousel-style visuals.

## Default Behavior

- Default platform/style: LinkedIn carousel.
- Default format: square image (`1:1`) unless the user specifies another size or platform.
- Default theme: **Blue / Orange Tech**.
- Use the existing `generate-image` skill/script for image generation.
- If the number of images is not specified, ask the user how many images to create before generating.
- If the post topic, audience, or message is unclear, ask a brief clarification before generating.

## Default Theme: Blue / Orange Tech

Use this palette unless the user provides another theme:

```text
Background:       #F8FAFC or #111827
Main text:        #111827 or #FFFFFF
Primary elements: #2563EB
Important hooks:  #F97316
Small highlights: #FACC15
Secondary text:   #64748B
```

Theme guidance:

- Prefer clean, modern, high-contrast layouts.
- Use `#2563EB` for primary UI shapes, frames, grids, and key visual elements.
- Use `#F97316` for hook emphasis, arrows, alerts, or strong contrast moments.
- Use `#FACC15` only for small highlights.
- Use `#64748B` for secondary/supporting text.
- Avoid adding colors outside the theme unless the user explicitly requests it.

## Template Workflow

Before generating final images, check whether the user wants to use a visual template/reference image.

### 1. User provides a template path

If the user provides a template/reference image path:

- Use that image as the visual reference for final generation.
- Force the image generation model to `openai/gpt-image-1.5`.
- Force `quality` to `low`.
- Use the highest available input fidelity setting.
- Continue directly to final image generation.
- Tell the user which template path is being used.

### 2. User wants to generate a template

If the user wants to generate a template/reference image first:

- Generate one template image before creating the final carousel/images.
- Force the template generation model to `openai/gpt-image-1.5`.
- Force `quality` to `low`.
- Save the template image to `~/Pictures/`.
- Stop after generating the template and ask the user to approve it.
- If the user rejects it or requests changes, iterate on the template only.
- Do not generate the final image set until the user approves the template.
- Once approved, use the approved template as the visual reference for final image generation.
- For final images, use:
  - `openai/gpt-image-1.5`
  - `quality: low`
  - the approved template as input/reference image
  - the highest available input fidelity setting

### 3. User does not want a template

If the user chooses not to use a template:

- Skip the reference-image workflow.
- Generate images normally using the default model/settings from the `generate-image` skill, unless the user specifies otherwise.

## Deterministic HTML Templates

Use deterministic HTML/CSS templates instead of image-generation models when the image needs exact text, exact code, or precise layout.

Available LinkedIn square templates live in:

```text
{skillDir}/templates/linkedin-square/
├── template.html        # reusable base template
├── template.css         # shared light/dark styles
└── example-isolate.html # populated example/proof
```

Template rules:

- Use `data-theme="dark"` or `data-theme="light"` on the `<html>` element.
- Use only the skill palette colors and alpha variants:
  - `#F8FAFC`
  - `#111827`
  - `#FFFFFF`
  - `#2563EB`
  - `#F97316`
  - `#FACC15`
  - `#64748B`
- For carousel images, keep the `<!-- PAGINATION START -->` block.
- For single-image posts, remove the pagination block.
- Edit content directly in HTML: headline, code lines, line numbers, bullets, filename, and labels.
- Keep exact code/text in HTML, not in image-generation prompts.

Rendering workflow:

1. Copy `template.html` to a descriptive working file, or copy an existing example.
2. Set `data-theme` to `light` or `dark`.
3. Edit headline/code/bullets and keep/remove pagination.
4. Render the file to PNG at `1080x1080` using the Playwright/browser workflow.
5. Save final PNG outputs directly to `~/Pictures/` unless the user specifies another path.
6. Do not create a project/topic subfolder unless the user explicitly asks for one.
7. Treat generated HTML/CSS as temporary render sources: keep them in a temp/work directory while rendering, then remove them after PNG QA unless the user explicitly asks to keep editable source files.
8. Report only final image file paths by default, not temporary HTML/CSS paths.
9. After rendering, visually inspect every generated image before reporting completion.
10. Check for oddness: overlays, out-of-bounds elements, cut-off text/code, underused space, typos, wrong code, bad pagination, and design flaws.
11. If anything is wrong, fix the HTML/CSS, regenerate the affected image, and inspect again.
12. Repeat the regenerate-and-inspect loop until each image is correct and polished.

Example Chrome-compatible render command:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
  --headless=new \
  --disable-gpu \
  --hide-scrollbars \
  --window-size=1080,1080 \
  --screenshot=~/Pictures/example.png \
  file:///{absolute-path-to-html}
```

Prefer the `playwright-browser` skill/CLI when available. Use browser screenshots only for rendering; do not use image-generation models for exact code/text images.

## Image Planning Workflow

For each social media image set:

1. Confirm or infer the platform and format.
2. Confirm the number of images; if missing, ask the user.
3. Check template preference using the Template Workflow above.
4. If exact text/code is required, use the deterministic HTML template workflow.
5. Create a concise slide/image plan:
   - image number
   - headline text
   - optional short subtitle
   - visual concept
6. Generate images using the selected theme and template/reference approach.
7. Save final PNG outputs directly to `~/Pictures/` with descriptive filenames.
8. Do not create a topic/project folder unless the user asks for one.
9. If the images will be used for LinkedIn scheduling through Buffer, upload the final PNGs to Cloudinary after QA. Use folder `linkedin/posts/{post-alias}/`, where `{post-alias}` is a short kebab-case alias confirmed by the user or safely derived from the post topic. Return the Cloudinary delivery URLs so Buffer can attach them as image assets.

   **Cloudinary upload:** Pass `file` and `folder` inside `upload_request`, not at the top level.
10. Do not leave generated HTML/CSS files behind unless the user asks for editable sources; remove temporary render files after final PNG QA.
11. Report generated PNG file paths by default. When Cloudinary hosting is used, also report the Cloudinary URLs.

## Text Rules for Generated Images

- Keep text short and readable.
- Prefer one strong headline plus optional short subtitle.
- Avoid dense body text inside images.
- Avoid engagement-bait phrasing unless the user explicitly asks for it.
- For technical posts, preserve exact API names, casing, punctuation, and symbols from the source material.
- If exact technical text matters, repeat it explicitly in the image prompt and avoid adding extra labels.

## Post Copy

If the user asks for post text alongside images:
- Defer to the `social-media-post` skill for content-first drafting.
- Handle directly only if it's a minor wording tweak on existing copy or image-overlay text.

For image-overlay text rules (headlines, captions inside images), see Text Rules for Generated Images above.

## Future Themes

Additional themes can be added using this structure:

```text
Theme name:
Background:
Main text:
Primary elements:
Important hooks:
Small highlights:
Secondary text:
Style notes:
```
