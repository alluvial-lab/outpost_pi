---
id: idea-broker-cwd-control-char-sanitization
created: 2026-11-19
updated: 2026-11-20
tags: [pi-extension, workflow]
---

# Sanitize control characters in broker-registered `cwd` / rendered `from` headers

Parked from `feat-mcp-push-turn-delivery` fresh-context review (Important, non-blocking).

## Context

`broker.ts` currently stores `req.cwd` as-is during peer registration, and `renderInboxMessage` (shared by `get_messages` and push-delivery batches) interpolates `from=${m.from}` unquoted. A local UDS peer registering a `cwd` containing newlines could forge header lines inside rendered message blocks (mitigated today by the same-user local UDS trust boundary where `body` is already untrusted model input).

## Direction

Reject or strip ASCII control characters (including `\r`/`\n`) from `req.cwd` at the broker registration boundary, or quote/escape `from` consistently across rendered envelope blocks without breaking existing `get_messages` readers.
