#!/usr/bin/env node
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { dirname, resolve, join, extname } from "node:path";
import { env, exit, argv } from "node:process";
import { homedir } from "node:os";
import Replicate from "replicate";

const DEFAULT_MODEL = "openai/gpt-image-1.5";
const DEFAULT_QUALITY = "low";
const DEFAULT_TIMEOUT = 300;
const DEFAULT_MIN_INTERVAL = 12;
const DEFAULT_RETRIES = 3;
const DEFAULT_RETRY_DELAY = 15;
const STATE_FILE = new URL(".last-generation.json", import.meta.url).pathname;

const MODELS = [
  { id: "openai/gpt-image-1.5", desc: "Default model. Strong prompt following and text rendering; defaults to quality=low for lower cost." },
  { id: "openai/gpt-image-2", desc: "Higher-fidelity OpenAI image model with reference image support." },
  { id: "xai/grok-imagine-image", desc: "Good typography and poster-style social graphics." },
  { id: "google/imagen-4-fast", desc: "Fast Imagen 4 variant; good balance of cost and quality." },
  { id: "google/imagen-3", desc: "Polished Google image generation model." },
  { id: "google/nano-banana", desc: "Google image model for lower-cost generation and editing." },
  { id: "google/nano-banana-2", desc: "Newer Nano Banana model with 1K/2K/4K resolution-based pricing." },
];

const IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif"]);
const EXT_TO_MIME = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".bmp": "image/bmp",
  ".tiff": "image/tiff",
  ".tif": "image/tiff",
};
const MIME_TO_EXT = {
  "image/png": ".png",
  "image/jpeg": ".jpg",
  "image/jpg": ".jpg",
  "image/gif": ".gif",
  "image/webp": ".webp",
  "image/bmp": ".bmp",
  "image/tiff": ".tiff",
};

function printUsage() {
  console.log(`Usage: node generate-image.mjs --prompt "<text>" [options]

Generate an image from a text prompt using the Replicate API.

Required:
  --prompt "..."        The text prompt describing the image to generate.

Optional:
  --model owner/name    Model to use (default: ${DEFAULT_MODEL}, quality=${DEFAULT_QUALITY})
  --output path         Output file or directory (default: ~/Pictures/timestamp.ext)
  --options '{"k":"v"}'   Extra model inputs as JSON string
  --input-image path    Input image path or URL (repeatable). Local files are converted to base64 data URIs.
  --input-images paths  Comma-separated input image paths or URLs.
  --input-fidelity val  Input fidelity for supported models (default: high when input images are used with openai/gpt-image-1.5)
  --timeout seconds     Max seconds to wait for generation (default: ${DEFAULT_TIMEOUT})
  --min-interval s      Minimum seconds between generation requests (default: ${DEFAULT_MIN_INTERVAL}, 0 to disable)
  --retries n           Max retries on 429 rate limit (default: ${DEFAULT_RETRIES})
  --retry-delay s       Base seconds to wait on 429 when reset time is unknown (default: ${DEFAULT_RETRY_DELAY})
  --no-retry            Disable retries on 429
  --help                Show this help message

Environment:
  REPLICATE_API_TOKEN   Required. Your Replicate API token.

Available models:`);
  for (const m of MODELS) {
    console.log(`  ${m.id} — ${m.desc}`);
  }
}

function parseArgs() {
  const args = argv.slice(2);
  const out = {
    prompt: null,
    model: DEFAULT_MODEL,
    output: null,
    options: null,
    timeout: DEFAULT_TIMEOUT,
    minInterval: DEFAULT_MIN_INTERVAL,
    retries: DEFAULT_RETRIES,
    retryDelay: DEFAULT_RETRY_DELAY,
    help: false,
    inputImages: [],
    inputFidelity: null,
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--help") { out.help = true; continue; }
    if (a === "--prompt") { out.prompt = args[++i]; continue; }
    if (a === "--model") { out.model = args[++i]; continue; }
    if (a === "--output") { out.output = args[++i]; continue; }
    if (a === "--options") { out.options = args[++i]; continue; }
    if (a === "--input-image") { out.inputImages.push(args[++i]); continue; }
    if (a === "--input-images") { out.inputImages.push(...args[++i].split(",").map((s) => s.trim()).filter(Boolean)); continue; }
    if (a === "--input-fidelity") { out.inputFidelity = args[++i]; continue; }
    if (a === "--timeout") { out.timeout = Number(args[++i]); continue; }
    if (a === "--min-interval") { out.minInterval = Number(args[++i]); continue; }
    if (a === "--retries") { out.retries = Number(args[++i]); continue; }
    if (a === "--retry-delay") { out.retryDelay = Number(args[++i]); continue; }
    if (a === "--no-retry") { out.retries = 0; continue; }
  }
  return out;
}

async function getLastGenerationTime() {
  try {
    const raw = await readFile(STATE_FILE, "utf-8");
    const data = JSON.parse(raw);
    if (typeof data?.lastGeneration === "number") {
      return data.lastGeneration;
    }
  } catch {
    // missing or corrupt state file is fine
  }
  return 0;
}

async function updateLastGenerationTime() {
  try {
    await writeFile(STATE_FILE, JSON.stringify({ lastGeneration: Date.now() }, null, 2));
  } catch {
    // state write failure is non-fatal
  }
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function applyPacing(minIntervalSeconds) {
  if (minIntervalSeconds <= 0) return;
  const last = await getLastGenerationTime();
  const elapsed = (Date.now() - last) / 1000;
  if (elapsed < minIntervalSeconds) {
    const waitSeconds = minIntervalSeconds - elapsed;
    console.log(`Rate-limit pacing: waiting ${waitSeconds.toFixed(1)}s before next request...`);
    await wait(waitSeconds * 1000);
  }
}

function parseRetryWaitFromError(err, fallbackDelaySeconds) {
  const message = err?.message || "";
  const detail = err?.detail || "";
  const body = err?.response?.body || "";
  const text = err?.response?.text || "";

  const combined = `${message} ${detail} ${body} ${text}`;
  const match = combined.match(/resets\s+in\s+~?(\d+(?:\.\d+)?)\s*s/i);
  if (match) {
    const seconds = parseFloat(match[1]);
    if (!isNaN(seconds) && seconds > 0) {
      // Add small jitter (1-3s) to avoid thundering herd
      const jitter = 1 + Math.random() * 2;
      return (seconds + jitter) * 1000;
    }
  }
  // Fallback: base delay + jitter
  const jitter = 1 + Math.random() * 2;
  return (fallbackDelaySeconds + jitter) * 1000;
}

async function runWithRetry(replicate, model, input, args) {
  const maxRetries = args.retries;
  const fallbackDelay = args.retryDelay;

  let lastErr = null;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    if (attempt > 0) {
      const waitMs = parseRetryWaitFromError(lastErr, fallbackDelay);
      const waitSec = (waitMs / 1000).toFixed(1);
      console.log(`Rate limit retry ${attempt}/${maxRetries}: waiting ${waitSec}s...`);
      await wait(waitMs);
    }

    try {
      const runPromise = replicate.run(model, { input });
      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error(`Prediction timed out after ${args.timeout} seconds`)), args.timeout * 1000);
      });
      return await Promise.race([runPromise, timeoutPromise]);
    } catch (err) {
      const status = getStatus(err);
      if (status === 429) {
        lastErr = err;
        continue; // retry
      }
      throw err; // non-429 errors bubble up immediately
    }
  }

  throw lastErr;
}

function inferExtensionFromUrl(url) {
  try {
    const u = new URL(url);
    const e = extname(u.pathname).toLowerCase();
    if (IMAGE_EXTS.has(e)) return e;
  } catch {}
  return null;
}

function inferExtensionFromContentType(ct) {
  if (!ct) return null;
  const main = ct.split(";")[0].trim().toLowerCase();
  return MIME_TO_EXT[main] || null;
}

function buildOutputPath(url, userOutput) {
  const now = new Date();
  const stamp =
    now.getFullYear() +
    String(now.getMonth() + 1).padStart(2, "0") +
    String(now.getDate()).padStart(2, "0") +
    "-" +
    String(now.getHours()).padStart(2, "0") +
    String(now.getMinutes()).padStart(2, "0") +
    String(now.getSeconds()).padStart(2, "0");

  const urlExt = inferExtensionFromUrl(url) || ".png";

  if (!userOutput) {
    return join(homedir(), "Pictures", `generated-image-${stamp}${urlExt}`);
  }

  const resolved = resolve(userOutput);
  const isDir = userOutput.endsWith("/") || userOutput.endsWith("\\");
  if (isDir) {
    return join(resolved, `generated-image-${stamp}${urlExt}`);
  }

  const userExt = extname(resolved).toLowerCase();
  if (IMAGE_EXTS.has(userExt)) {
    return resolved;
  }

  return join(resolved, `generated-image-${stamp}${urlExt}`);
}

function extractUrls(value, seen = new Set(), out = [], urls = new Set()) {
  if (!value || seen.has(value)) return out;
  if (typeof value === "string") {
    if (/^https?:\/\//.test(value) && !urls.has(value)) {
      urls.add(value);
      out.push(value);
    }
    return out;
  }
  seen.add(value);
  if (Array.isArray(value)) {
    for (const item of value) extractUrls(item, seen, out, urls);
  } else if (typeof value === "object") {
    if (typeof value.url === "string") extractUrls(value.url, seen, out, urls);
    for (const v of Object.values(value)) extractUrls(v, seen, out, urls);
  }
  return out;
}

function redactSensitive(value) {
  return value
    .replace(/Bearer\s+[a-zA-Z0-9_\-]{8,}/g, "Bearer [redacted]")
    .replace(/Token\s+[a-zA-Z0-9_\-]{8,}/g, "Token [redacted]")
    .replace(/api[_-]?key[:\s=]+[a-zA-Z0-9_\-]{8,}/gi, "api_key=[redacted]")
    .replace(/Authorization[:\s]+[^\s;,]+/gi, "Authorization: [redacted]");
}

function extractErrorDetails(err) {
  const details = {};
  const keys = ["status", "statusCode", "code", "detail", "title", "cause"];
  for (const key of keys) {
    if (err?.[key] != null) {
      details[key] = redactSensitive(String(err[key]));
    }
  }
  if (err?.response?.text != null) {
    details["responseBody"] = redactSensitive(String(err.response.text));
  } else if (err?.response?.body != null) {
    details["responseBody"] = redactSensitive(String(err.response.body));
  }
  if (err?.response?.status != null) {
    details["responseStatus"] = String(err.response.status);
  }
  if (Object.keys(details).length === 0) return "";
  return " Details: " + JSON.stringify(details);
}

function getStatus(err) {
  return err?.status || err?.statusCode || err?.response?.status;
}

function formatError(err) {
  const msg = err?.message || String(err);
  const status = getStatus(err);
  const details = extractErrorDetails(err);

  if (status === 401 || msg.includes("401") || msg.includes("Unauthorized")) {
    return `Error 401: Invalid or missing Replicate API token. Check your REPLICATE_API_TOKEN.${details}`;
  }
  if (status === 402 || msg.includes("402") || msg.includes("Payment")) {
    return `Error 402: Replicate billing issue. Check your account balance.${details}`;
  }
  if (status === 429 || msg.includes("429") || msg.includes("Rate limit")) {
    return `Error 429: Rate limited by Replicate. Wait a moment and retry.${details}`;
  }
  if ((status && status >= 500 && status < 600) || (msg.includes("5") && /5\d{2}/.test(msg))) {
    return `Error: Replicate server error. Try again later. (${msg})${details}`;
  }
  return `Error: ${msg}${details}`;
}

function isUrl(str) {
  try {
    const u = new URL(str);
    return u.protocol === "http:" || u.protocol === "https:";
  } catch {
    return false;
  }
}

function inferMimeFromExt(filePath) {
  return EXT_TO_MIME[extname(filePath).toLowerCase()] || "image/png";
}

async function fileToDataUri(filePath) {
  const buffer = await readFile(filePath);
  const mime = inferMimeFromExt(filePath);
  const base64 = buffer.toString("base64");
  return `data:${mime};base64,${base64}`;
}

async function resolveInputImages(pathsOrUrls) {
  const resolved = [];
  for (const p of pathsOrUrls) {
    if (isUrl(p)) {
      resolved.push(p);
    } else {
      const absPath = resolve(p);
      try {
        const uri = await fileToDataUri(absPath);
        resolved.push(uri);
      } catch (err) {
        console.error(`Failed to read input image: ${absPath} — ${err.message}`);
        exit(1);
      }
    }
  }
  return resolved;
}

function mapInputImages(model, images) {
  if (model === "openai/gpt-image-1.5" || model === "openai/gpt-image-2") {
    return { field: "input_images", values: images };
  }
  if (model === "google/nano-banana" || model === "google/nano-banana-2") {
    return { field: "image_input", values: images };
  }
  if (model === "xai/grok-imagine-image") {
    if (images.length > 1) {
      console.warn(`Warning: model ${model} only supports one input image. Using the first image.`);
    }
    return { field: "image", values: images[0] };
  }
  return { field: null, values: null };
}

async function main() {
  const args = parseArgs();

  if (args.help) {
    printUsage();
    exit(0);
  }

  if (!env.REPLICATE_API_TOKEN) {
    console.error("Missing REPLICATE_API_TOKEN environment variable. Set it and try again.");
    exit(1);
  }

  if (!args.prompt || !args.prompt.trim()) {
    console.error("Missing required --prompt argument.");
    printUsage();
    exit(1);
  }

  const model = args.model.trim();
  if (!model.includes("/")) {
    console.error(`Invalid model format "${model}". Must be "owner/name". Available models are listed in --help.`);
    exit(1);
  }

  const input = { prompt: args.prompt.trim() };
  if (args.options) {
    try {
      const parsed = JSON.parse(args.options);
      Object.assign(input, parsed);
    } catch (e) {
      console.error(`Invalid --options JSON: ${e.message}`);
      exit(1);
    }
  }

  if (model === "openai/gpt-image-1.5" && input.quality == null) {
    input.quality = DEFAULT_QUALITY;
  }

  const images = args.inputImages;

  if (images.length > 0) {
    const resolvedImages = await resolveInputImages(images);
    const mapping = mapInputImages(model, resolvedImages);

    if (mapping.field) {
      if (input[mapping.field] == null) {
        input[mapping.field] = mapping.values;
      }
    } else {
      const hasExplicitImageField = input.input_images != null || input.image_input != null || input.image != null;
      if (!hasExplicitImageField) {
        console.warn(`Warning: model ${model} may not support input images. Skipping --input-image unless provided via --options.`);
      }
    }

    if (model === "openai/gpt-image-1.5") {
      if (input.input_fidelity == null && args.inputFidelity != null) {
        input.input_fidelity = args.inputFidelity;
      }
      if (input.input_fidelity == null) {
        input.input_fidelity = "high";
      }
    }
  }

  await applyPacing(args.minInterval);

  const replicate = new Replicate({ auth: env.REPLICATE_API_TOKEN, useFileOutput: false });

  console.log(`Creating prediction on Replicate with model: ${model}`);

  let output;
  try {
    output = await runWithRetry(replicate, model, input, args);
  } catch (err) {
    console.error(formatError(err));
    exit(1);
  }

  await updateLastGenerationTime();

  const urls = extractUrls(output);

  if (urls.length === 0) {
    console.error("Prediction succeeded but no image URLs were found in the output.");
    console.error("Raw output:", JSON.stringify(output, null, 2));
    exit(1);
  }

  console.log(`Image URLs found: ${urls.length}`);
  for (const u of urls) console.log(`  ${u}`);

  const firstUrl = urls[0];
  const outPath = buildOutputPath(firstUrl, args.output);
  await mkdir(dirname(outPath), { recursive: true });

  const imgRes = await fetch(firstUrl);
  if (!imgRes.ok) {
    console.error(`Failed to download image: ${imgRes.status} ${imgRes.statusText}`);
    exit(1);
  }

  const blob = await imgRes.arrayBuffer();
  const ctExt = inferExtensionFromContentType(imgRes.headers.get("content-type"));
  const finalPath = ctExt && !extname(outPath) ? outPath + ctExt : outPath;

  await writeFile(finalPath, Buffer.from(blob));
  console.log(`Saved: ${finalPath}`);
  exit(0);
}

main().catch((err) => {
  console.error("Unexpected error:", err.message || err);
  exit(1);
});
