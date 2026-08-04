---
id: story-mobile-slash-command-extension-action
kind: story
stage: implementing
tags: [pi-extension, app]
parent: feature-mobile-slash-command-invocation
depends_on: [story-mobile-slash-command-passthrough-editor]
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# Extension command-submission action + wire

Unit B of `feature-mobile-slash-command-invocation`. Expose a wire action that
drives the editor-seam, and retire the fragile `ctx.newSession()` path (the
original `/new` bug).

## Change

- `pi-extension/src/actions/handlers.ts` + `index.ts` — a `slash_command`
  `{ command }` action (and/or extend `session_new`) that calls
  `editor.onSubmit(cmd)` (Unit A's seam).
- Map the existing `session_new` action → `onSubmit("/new")` and REMOVE the
  `if (!ctx?.newSession) throw "newSession unavailable…"` path
  (`handlers.ts:225`) — the original bug.
- Ack/error: `onSubmit` returns `void` → confirm via lifecycle events
  (`session_start reason=new` for `/new`, etc.); emit a structured
  `action_ok`/`action_error`.
- Wire schema: add the action to `protocol/schema/app-pi-client.schema.json` +
  the dart IR fixture; regenerate TS + dart (Rust unchanged).

## Acceptance

- [ ] App `slash_command("/reload")` → pi reloads; `session_new` → new session
      via `/new` (not the old `ctx.newSession()` path).
- [ ] Structured ack/error (success confirmed via lifecycle, not fire-and-forget).
- [ ] `check:protocol` clean; the old `newSession unavailable` throw is gone.
- [ ] Extension tests green (`corepack pnpm test`).

## Ordering

`depends_on: [story-mobile-slash-command-passthrough-editor]` (needs the editor
seam). Unblocks C + D.
