---
name: generate-image
description: |
  Generates images from text prompts using the Replicate API.
  Use when the user asks to create, generate, or draw an image from a description.
  Supports multiple models including Ideogram, FLUX, and Google Imagen.
compatibility: Requires Node.js 18+, a Replicate account, and the REPLICATE_API_TOKEN environment variable.
---

# Generate Image

Generate images via Replicate using a bundled Node.js script.

## Prerequisites

- `REPLICATE_API_TOKEN` must be set in the environment. If it is not present, **do not run** the generation script; inform the user and stop.

## Available Models

| Use case | Model | Notes |
|---|---|---|
| Default low-cost social image | `openai/gpt-image-1.5` | Default model. Uses `quality: low` automatically unless overridden with `--options`. Supports reference images via `--input-image` / `--input-images` and `input_fidelity`. Strong prompt following and typography. |
| Higher-fidelity OpenAI image model | `openai/gpt-image-2` | Supports reference images via `--input-image` / `--input-images`. High input fidelity by default. |
| Poster-style social graphics | `xai/grok-imagine-image` | Good for graphic/poster-like outputs and readable text. Supports one reference/edit image via `--input-image`. |
| Fast balanced Google model | `google/imagen-4-fast` | Fast Imagen 4 variant. Replicate pricing observed at $0.02/output image. |
| Polished Google model | `google/imagen-3` | Good polished general-purpose generation. Replicate pricing observed at $0.05/output image. |
| Budget Google image/editing | `google/nano-banana` | Lower-cost Google model. Replicate pricing observed at $0.039/output image. |
| Newer Nano Banana model | `google/nano-banana-2` | Supports resolution-based pricing: 1K/2K/4K. Replicate pricing observed at $0.067/$0.101/$0.151 per output image. |

Default model: `openai/gpt-image-1.5` with `quality: low`

## Usage

Always invoke the bundled helper script with an absolute path (or `cd` into the skill directory first):

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs --prompt "a cinematic robot painting"
```

Save to a specific file:

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "a cinematic robot painting" \
  --output ~/Desktop/robot.png
```

Use a different model:

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "a vintage travel poster" \
  --model black-forest-labs/flux-1.1-pro
```

Pass additional model options (JSON). For `openai/gpt-image-1.5`, `quality` defaults to `low`; override it here if needed:

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "a cat in a hat" \
  --options '{"aspect_ratio":"1:1","quality":"medium"}'
```

Use a local image or URL as a visual reference/template:

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "create a matching carousel slide in this style" \
  --input-image ~/Pictures/template.png \
  --input-fidelity high \
  --options '{"aspect_ratio":"1:1"}'
```

Use multiple reference images:

```bash
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "create a new image matching these references" \
  --input-images ~/Pictures/ref-1.png,~/Pictures/ref-2.png \
  --options '{"aspect_ratio":"1:1"}'
```

Reference image mapping by model:

- `openai/gpt-image-1.5` and `openai/gpt-image-2`: sent as `input_images`.
- `google/nano-banana` and `google/nano-banana-2`: sent as `image_input`.
- `xai/grok-imagine-image`: sends only the first image as `image`.
- Other models may not support reference images; the script warns and skips attaching them.

For `openai/gpt-image-1.5`, when reference images are provided, `input_fidelity` defaults to `high` unless overridden with `--input-fidelity` or `--options`. Higher fidelity may cost more.

Control rate-limit pacing and retries:

```bash
# Wait at least 20s between requests, retry up to 5 times on 429
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "a scenic mountain landscape" \
  --min-interval 20 \
  --retries 5

# Disable retries entirely for immediate failure on rate limit
node ~/.pi/agent/skills/generate-image/generate-image.mjs \
  --prompt "a logo design" \
  --no-retry
```

## Rate Limit Handling

Replicate rate limits may throttle rapid sequential requests. The script includes built-in pacing and retry logic:

- **Pacing**: By default, waits at least `12` seconds between generation requests to avoid bursts. Override with `--min-interval 5` or disable with `--min-interval 0`.
- **Retry on 429**: If Replicate returns a rate limit, the script retries up to `3` times by default. It attempts to parse Replicate's reset time from the error message and waits accordingly. Override with `--retries 5` or disable with `--no-retry`.
- **Custom retry delay**: When Replicate does not specify a reset time, the script waits `15` seconds plus jitter between retries. Override with `--retry-delay 30`.

## Behavior

- Default output directory is `~/Pictures/`.
- The script will create the output directory if it does not exist.
- If image generation fails for any reason (API error, timeout, prediction failure), **stop and inform the user** with the error details so they can sort it out.
- Do not hand-roll API calls; always use the bundled `generate-image.mjs` script.
