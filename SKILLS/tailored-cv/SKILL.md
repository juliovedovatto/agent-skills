---
name: tailored-cv
description: Tailor Julio Vedovatto's CV for specific job descriptions using the saved HTML template. Use when asked to create, adapt, translate, verify, or screenshot a tailored CV PDF for a company, role, skill focus, or job description PDF/link.
---

# Tailored CV

Use this skill to generate tailored CV PDFs from Julio's saved HTML template.

## Paths

Base CV directory:

`/Users/juliovedovatto/Library/CloudStorage/GoogleDrive-juliovedovatto@gmail.com/Meu Drive/Curriculo`

Tailored directory:

`/Users/juliovedovatto/Library/CloudStorage/GoogleDrive-juliovedovatto@gmail.com/Meu Drive/Curriculo/Tailored`

Template:

`/Users/juliovedovatto/Library/CloudStorage/GoogleDrive-juliovedovatto@gmail.com/Meu Drive/Curriculo/Tailored/Julio-Vedovatto-Full-Stack-Developer-Tailored.html`

Prospect output directory:

`/Users/juliovedovatto/Library/CloudStorage/GoogleDrive-juliovedovatto@gmail.com/Meu Drive/Curriculo/Tailored/Prospects`

Screenshot/output review directory:

`/Users/juliovedovatto/tmp/.pi`

## Default Workflow

1. Read or extract the job description.
   - If PDF: extract text with Ghostscript `txtwrite`.
   - If URL: use web/search/fetch tools.
   - If text pasted by user: analyze it directly.
2. Identify:
   - role title
   - required stack
   - nice-to-have stack
   - responsibilities
   - seniority
   - keywords
   - unsupported or risky claims
3. Read the HTML template.
4. Create a temporary tailored HTML in `Tailored/Prospects`.
5. Generate a PDF in `Tailored/Prospects` using Google Chrome headless.
6. Verify page count with Ghostscript.
7. Review/QA the final CV against the job description.
8. If review finds gaps, unsupported claims, or weak alignment:
   - report what is missing
   - ask the user for clarification/input before making stronger claims
   - do not silently invent experience
9. Remove the temporary tailored HTML unless the user explicitly asks to keep it.
10. Return only:
   - final PDF path
   - page count
   - verification summary
   - review/QA summary
   - screenshot path if screenshot was requested

## Review / QA Step

Before reporting completion, use a reviewer or QA agent when available.

The reviewer should compare:
- job description requirements
- tailored CV title
- summary
- skills
- experience bullets
- keyword coverage
- truthfulness / unsupported claims
- page count and layout constraints

Reviewer output should answer:

1. Does the CV clearly align with the role?
2. Are the most important JD keywords represented?
3. Are any required skills missing or under-emphasized?
4. Are there any strong claims that need user confirmation?
5. Is the CV still readable and concise?
6. Should we ask the user for input before finalizing?

If the reviewer identifies missing confirmed experience, ask the user before adding it.

Example:

```txt
Review found a gap: the JD asks for OAuth2/OIDC, but the template does not confirm this experience. Should I add OAuth2/OIDC experience, or keep it as general authentication flow familiarity?
```

Do not finalize a risky claim without user confirmation.

## Output Rules

- Final prospect CVs should be PDFs in `Tailored/Prospects`.
- Remove generated `.html` files after PDF generation by default.
- Do not overwrite the base template.
- Use clear filenames based on company, role, or skill focus.

Examples:

- `Julio-Vedovatto-Frontend-Engineer-Svelte.pdf`
- `Julio-Vedovatto-Senior-Vue-Frontend-Engineer.pdf`
- `Julio-Vedovatto-Full-Stack-React-Developer.pdf`
- `Julio-Vedovatto-Contabilizei-Frontend-Senior-Vue.pdf`

## Content Rules

Preserve the same full work history unless the user explicitly asks to remove, compress, or reorder roles.

Tailor only:
- headline/title
- summary
- skills
- emphasis inside bullets
- keyword alignment
- language/locale if requested

Keep claims truthful.

Do not claim direct experience with a tool unless:
- it exists in the template,
- the user stated it,
- or prior session/context confirms it.

If a JD asks for a tool that is not confirmed, either ask the user first or use softer truthful wording, such as:

- “modern frontend practices”
- “component-driven architecture”
- “accessibility-minded UI”
- “familiarity with...”
- “worked alongside...”
- “supported integrations involving...”

Ask before adding strong claims like:
- production experience with a specific unconfirmed framework
- WCAG audits
- OAuth2/OIDC
- Svelte 5 runes
- Pinia/Vue Router
- Vuetify/Quasar
- Tailwind production expertise
- shadcn/Radix/bits-ui

## Language Rules

- If the job description is in Portuguese or the user asks for pt_BR, generate the CV in Brazilian Portuguese.
- Otherwise, default to English.
- Keep role names natural for the language.
- Do not over-translate technology names.

Examples:
- “Senior Front-End Engineer” can stay in English for English CVs.
- “Desenvolvedor Front-End Sênior” for pt_BR CVs.
- Keep “React”, “Node.js”, “SvelteKit”, “GraphQL”, etc.

## PDF Generation

Use Google Chrome headless for PDF generation.

Chrome binary:

`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`

Command:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
  --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf="$PDF_PATH" \
  "file://$HTML_PATH"
```

Notes:
- Use quoted paths because the Google Drive path contains spaces.
- Do not use `/opt/homebrew/bin/chromium`; it was previously broken on this machine.
- Prefer direct Chrome for PDF generation over Playwright because Chrome handles `file://` HTML directly without requiring a temporary HTTP server.

## Page Count Verification

Use Ghostscript bbox:

```bash
/opt/homebrew/bin/gs \
  -q -dNOPAUSE -dBATCH \
  -sDEVICE=bbox \
  "$PDF_PATH"
```

Count `%%HiResBoundingBox` occurrences as pages.

If page count is more than requested:
- tighten section spacing
- reduce experience bullet font size slightly
- shorten summary or skills wording
- avoid removing roles unless user approves

## Screenshot Review

If the user asks for a screenshot or visual QA, render PDF pages with Ghostscript:

```bash
/opt/homebrew/bin/gs \
  -q -dNOPAUSE -dBATCH \
  -sDEVICE=png16m \
  -r120 \
  -sOutputFile="/Users/juliovedovatto/tmp/.pi/cv-page-%d.png" \
  "$PDF_PATH"
```

Then inspect the generated PNGs visually before reporting.

Screenshot paths should be under:

`/Users/juliovedovatto/tmp/.pi`

Do not delete screenshots unless the user asks.

## Job PDF Extraction

For PDF job descriptions, extract text with Ghostscript:

```bash
/opt/homebrew/bin/gs \
  -q -dNOPAUSE -dBATCH \
  -sDEVICE=txtwrite \
  -sOutputFile=- \
  "$JOB_PDF"
```

Analyze the extracted text for requirements and keywords before tailoring.

## Visual/Layout Guidelines

- Target one page by default.
- Preserve readability.
- Avoid skills wrapping awkwardly where possible.
- Keep section spacing compact but readable.
- Skills can be slightly larger than experience bullets.
- Experience bullets can be smaller if needed to fit one page.
- Always verify after regeneration.

## Communication Style

When reporting results, be concise.

Return:

```txt
Done.

Generated:
/path/to/final.pdf

Verified:
- Pages: 1
- Temporary HTML removed
- Tailored for: <main stack/role keywords>

Review:
- Alignment: good / needs input
- Missing or risky claims: <brief summary>
```

If there are risks or unsupported claims, ask for input before finalizing those claims.
