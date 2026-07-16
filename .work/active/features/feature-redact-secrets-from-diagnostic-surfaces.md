---
id: feature-redact-secrets-from-diagnostic-surfaces
kind: feature
stage: drafting
tags: [app, pi-extension, cockpit, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-16
---

# Redact sensitive content from diagnostic and transcript surfaces

## Brief

Three security gate findings describe user/process content written verbatim to
logs or the transcript side-channel — a confidentiality leak on any shared
capture (bug report, screenshot, stderr paste). This feature defines a redaction
boundary for diagnostic surfaces:

- `gate-security-outbound-message-previews-logged` — outbound message previews (up to 80 chars of user text) written to logs
- `gate-security-raw-rpc-traffic-logged` — raw RPC stdout (prompts, tool results, image base64, relay/pairing tokens) printed to debug logs
- `gate-security-raw-stderr-in-transcript` — raw child stderr surfaced verbatim as a transcript side-channel

## Simplification opportunity

Apply a redaction filter at the log/transcript boundary (truncate or hash user
message text, redact known-secret shapes like tokens/base64 images). Preserve
the diagnostic value (the *fact* of a message, its id, routing) without the
content. No change to non-diagnostic behavior.

## Source

Promoted from backlog by `scope` (2026-07-15). 3 `gate-security-*-logged` /
`gate-security-raw-stderr-*` findings from the v0.6.0 release `gate-security`
pass.
