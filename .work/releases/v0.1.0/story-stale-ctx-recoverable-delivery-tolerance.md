---
id: story-stale-ctx-recoverable-delivery-tolerance
kind: story
stage: done
tags: [pi-extension, app, bug, transport]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-08
updated: 2026-07-08
implemented: 2026-07-08
review_addressed: 2026-07-08
split_from: story-fix-stale-ctx-messageapi-rearm-on-reload
---

# Tolerance layer for recoverable wake failures (`delivery_pending` + bounded replay queue)

## Brief

Split out of `story-fix-stale-ctx-messageapi-rearm-on-reload` (2026-07-08) when
the corrected root cause showed that story's *self-heal* premise was wrong. This
story is the **tolerance/mitigation** layer — correct, reviewed, and useful on
its own, independent of the (still-open, SDK-blocked) self-heal.

When `_wakeAgent` returns a recoverable failure (null `messageApi` during a
session replacement window OR a genuinely-stale ctx), the old behavior was:
`console.warn` + return **without telling the phone** → the phone's 20s
`send_timeout` → a permanent "not delivered" bubble with no retry (the
operator's "stuck in my mobile chat" symptom). This story replaces that silent
drop with a transient `delivery_pending` signal + a bounded replay queue.

## What shipped (commits `cadf2ff` + `8a8c058`)

- **`delivery_pending` wire signal** (new `knownErrorCode` in
  `protocol/schema/defs/app-pi-common.schema.json`; TS + Dart bindings
  regenerated; `PROTOCOL.md` updated). On a recoverable wake failure, the
  extension sends `error{code:"delivery_pending"}` to the phone instead of
  silence.
- **Bounded inbound replay queue** (`pi-extension/src/index.ts`): max 2
  entries, TTL 5s. A recoverable message is stashed + `delivery_pending` sent.
  On the next `bindApi` (or `withSession` re-arm), the queue drains and
  re-attempts delivery; on TTL expiry (or second replacement) it surfaces a
  real `internal_error` (no infinite queue, no silent loss).
- **App-side `delivery_pending` handling** (`app/lib/data/sync/sync_service.dart`):
  disarms the 20s `send_timeout` for that message (no permanent "not delivered"
  scar), re-arms a 60s fallback window for the genuine-failure case.

## What this does NOT do (explicitly)

This is **tolerance, not self-heal.** It does not fix the stuck-null
`messageApi` after `/new`/`/resume`/`/fork` (the actual bug the operator hit —
`messageApi` goes null via `forget()` and nothing re-arms it until a `/reload`).
The queue drains on `bindApi`, which is the `/reload` the operator must do
anyway. So even deployed, this replaces a silent 20s timeout with a
`delivery_pending` bubble (real UX win — no permanent scar) but the message
still does not deliver without a workstation `/reload`. The self-heal is the
open scope of `story-fix-stale-ctx-messageapi-rearm-on-reload` (SDK-blocked).

## Acceptance Criteria

- [x] A recoverable wake failure sends `delivery_pending` to the phone, not
      silence.
- [x] The phone disarms the 20s `send_timeout` on `delivery_pending` (no
      permanent "not delivered" scar).
- [x] A message stashed in the queue is delivered on the next `bindApi` (and
      on `withSession` re-arm — the mobile `session_new` path).
- [x] A queue entry that doesn't recover within TTL (5s) surfaces a real
      `internal_error`.
- [x] Bounded queue (max 2) drops oldest as `internal_error` when exceeded.
- [x] `flutter analyze` + `flutter test` clean; `corepack pnpm typecheck` +
      `corepack pnpm test` clean.
- [x] Two cross-model review passes (`openai-codex/gpt-5.5`, deep lane):
      Request changes (withSession drain + overflow test) → Approve.

## Implementation notes

- Files: `protocol/schema/defs/app-pi-common.schema.json`,
  `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`,
  `pi-extension/src/protocol/generated/protocol.generated.ts`,
  `app/lib/data/sync/sync_service.dart`,
  `app/test/data/sync/sync_service_test.dart`,
  `app/lib/protocol/generated/protocol.g.dart`,
  `tools/protocol-codegen/bin/protocol-codegen.mjs`,
  `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, `PROTOCOL.md`.
- Tests: pi-extension (stale enqueue, TTL expiry, bindApi replay, withSession
  drain, overflow); app (`delivery_pending` extends no-echo window).
- Discrepancy: Dart protocol generation used the committed Dart IR fixture;
  generator/fixture extended to emit `KnownErrorCode.deliveryPending` while
  keeping `ErrorMessage.code` an open string.
- Verification: pi-extension 769/769 pass; app analyze + sync_service tests
  clean.

## References

- Parent feature: `feature-session-stable-message-delivery`.
- Split from / self-heal counterpart: `story-fix-stale-ctx-messageapi-rearm-on-reload`.
- Corrected root cause (stuck-null after /new/resume/fork): see that story's
  "CORRECTED root cause" section.
- Parked `/reload` button mitigation: `.work/backlog/idea-mobile-session-control.md`.
- Parked full process-restart: `.work/backlog/idea-mobile-restart-pi-session-affordance.md`.
