---
name: buffer
description: |
  Schedule, queue, edit, and delete social-media posts on LinkedIn and other
  platforms via the Buffer MCP server. Use when the user mentions buffer,
  schedule, queue, linkedin, publish, reschedule, drafts, or ideas that need
  a publishing date.
compatibility: Requires the Buffer MCP server at https://mcp.buffer.com/mcp with BUFFER_API_KEY configured.
---

# Buffer

Schedule, queue, edit, and delete social-media posts through Buffer.

## When to use

- "Schedule this post for Tuesday"
- "Queue this in Buffer"
- "Publish to LinkedIn"
- "Reschedule the draft about X"
- "What's in my Buffer queue?"
- "Delete that scheduled post"

## 1. Connection gate

The first Buffer action in any session must be a live `buffer_get_account`
probe. A cached tool list does not prove connectivity — Pi may show
`not connected, cached`. On failure, stop and report which case applies:

- **No MCP entry** — `buffer` is missing from `~/.pi/agent/mcp.json`.
- **Auth failure** — `BUFFER_API_KEY` is missing or expired.
- **Unreachable** — the server at `https://mcp.buffer.com/mcp` is down.

Never print or echo `BUFFER_API_KEY` or the contents of
`~/.pi/agent/settings.json`.

## 2. Organization and channel discovery

`organizationId` comes from `organizations[].id` in the account response, never
the top-level account `id`. The two can look nearly identical; mixing them
returns a misleading "Organization not found" 500.

After selecting the organization, call `buffer_list_channels` and use an exact
returned channel `id`. Never guess or reuse IDs. Name the organization and
channel to the user before writing. Use `buffer_get_channel` to see the
posting schedule when queueing.

## 3. Creating a post

`buffer_create_post` requires:

- `organizationId` — from step 2.
- `channelId` — single string, not `channelIds`.
- `schedulingType` — `automatic` (auto-publish) or `notification` (manual
  approval).
- `text` — the post body.

`mode` defaults to `addToQueue`. Use `customScheduled` with `dueAt` only when
the user names a specific time; use `shareNow` only on explicit instruction
since it publishes immediately.

Build `dueAt` as ISO 8601 with the offset from the account `timezone`. Anchor
relative dates like "next Tuesday" on the `currentTime` returned by
`buffer_get_account` rather than an assumed date. `dueAt` must be in the
future.

On a validation error, read the "Expected parameters" block in the error
before retrying. Check `buffer_list_posts` before retrying an ambiguous
create so you do not double-schedule.

## 4. Link previews

When a post has no images and contains a URL, extract Open Graph metadata
via `~/.pi/agent/skills/social-media-post/scripts/og-scraper.sh` (`curl`/`wget`
are hook-blocked) and pass a single `assets[].link` entry with `url`, `title`,
`description`, `thumbnailUrl`. Buffer populates the LinkedIn link attachment
from it; do not hand-set `metadata.linkedin.linkAttachment`. A bare URL in
the text is not enough. Never mix images and a link preview on LinkedIn.

## 5. Editing and deleting

Before `buffer_edit_post`, call `buffer_get_post` and confirm `updatePost` is
in `allowedActions`. `schedulingType` is required on every edit. Omit `mode`
and `dueAt` unless rescheduling, since sending `mode` reschedules even when
unchanged. Edits are revalidated as a whole post and not merged, so carry
existing `assets` and `metadata` forward and change only what was asked.

`buffer_delete_post` is irreversible, requires `deletePost` in
`allowedActions`, and requires explicit user approval before the call.

## 6. Verify and report

After any write, call `buffer_get_post` and report:

- Post ID
- Channel
- Scheduled time converted back to the account timezone (Buffer returns
  `dueAt` in UTC)
- Whether the link preview attached
- Any error

## 7. Limits and errors

Buffer rate limits are per client and shared across all requests; back off
when an advisory appears. Scheduled-post quota is per plan (this org allows
10), so surface quota errors to the user instead of retrying.

## 8. Skill boundary

`buffer` owns MCP mechanics: connection, IDs, scheduling, edit/delete, and
verification. `social-media-post` owns caption text and the
image-versus-link-preview asset decision. See
`~/.pi/agent/skills/social-media-post/SKILL.md` for caption drafting.
