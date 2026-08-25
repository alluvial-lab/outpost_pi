---
id: story-canonical-transcript-timestamp-ownership-error-frame-ts
kind: story
stage: implementing
tags: [pi-extension, app, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log]
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-25
---

# Error-frame ts (schema + extension + app + codegen)

Unit C of `feature-canonical-transcript-timestamp-ownership`. The error path is
schema-spanning (same shape as the prior feature's Unit 1), so it's its own
checkpoint. Today error diagnostics have no wire `ts`; the app stamps phone
time on an authoritative bubble.

## Change

- `protocol/schema/app-pi-server.schema.json` — add optional `ts` (integer,
  min 0) to the `error` message definition, mirroring the existing optional-`ts`
  pattern.
- `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` (the dart
  source-of-truth) — add optional `ts` to the error member; regenerate:
  - TS: `corepack pnpm generate:protocol` (from `pi-extension/`,
    `COREPACK_HOME=/tmp/corepack-home corepack pnpm --store-dir /tmp/pnpm-store …`).
  - Dart: `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart
    --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out
    app/lib/protocol/generated/protocol.g.dart`.
  - Rust: unchanged (app-pi excluded from rust codegen).
- `pi-extension/src/index.ts` error producers (`provider_error`,
  `internal_error`, other renderable codes — NOT control-only codes like
  `unknown_peer`/`session_mismatch`/`delivery_pending`) — stamp the computed
  server `ts`.
- `app/lib/data/sync/sync_service.dart` — error diagnostic consumes wire `ts`
  with the `DateTime.now()` fallback for old extensions.

## Acceptance

- [ ] Optional `ts` on error frames; regenerated TS + Dart; `check:protocol`
  clean; regenerated dart `flutter analyze` clean.
- [ ] Extension stamps `ts`; app consumes it; error diagnostic no longer
  phone-timestamped (producer-connected tests).

## Ordering

`depends_on: [epic-durable-transcript-ownership-durable-event-log]`
(needs F1's durable ownership foundation; parallel with B); unblocks D.
