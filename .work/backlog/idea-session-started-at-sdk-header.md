---
id: idea-session-started-at-sdk-header
created: 2026-07-19
updated: 2026-07-19
tags: [pi-extension, app, protocol]
---

Reconcile `session_started_at` with the Pi SDK session header. The extension
currently initializes it lazily through `ensureSessionStarted()` when relay
service starts (or to `Date.now()` on app-triggered new-session reset), while
the installed SDK exposes the persisted session header timestamp through
`ctx.sessionManager.getHeader()`. The app uses `session_started_at` as
same-session replay ordering/high-water metadata, not identity. Audit whether
the SDK header timestamp should become the authoritative source and cover
startup, resume, fork, new, daemon, and in-memory sessions before changing the
wire semantics.

Surfaced by the evidence harvest in `feature-contract-gap-audit`; it is a
separate design-bearing fix, not part of that audit.
