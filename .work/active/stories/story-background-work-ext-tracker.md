---
id: story-background-work-ext-tracker
kind: story
stage: done
tags: [pi-extension, ux]
parent: feature-background-work-working-state
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Background-work tracker + RoomMeta.background + restart-gate hardening

Design checkpoint 1 of `feature-background-work-working-state`
(Units 1-3 in the feature body — read it for full interfaces, notes, and
acceptance criteria).

## Scope

1. **BackgroundActivityTracker** (`pi-extension/src/extension/background_activity.ts`)
   — id set fed by `subagents:created`/`completed`/`failed`/`resumed`
   from the `pi.events` bus, structural payload narrowing, transitions
   only.
2. **RoomMeta.background** — additive optional field through
   `relay_client.ts` → `relay_transport.ts` sendRoomMeta patch type →
   `_publishRoomMetaPatch` in `index.ts`; tracker wired in
   `composition_root.ts` beside `observeChildLifecycle`; session reset
   paths clear + publish false.
3. **Restart-gate hardening** — `_maybeRestartForExtensionReload` defers
   while background is active (does not consume the armed request);
   drain-to-zero re-attempts with the stored settled ctx.

## Acceptance evidence

- Fake-bus unit tests for the tracker (transitions, malformed payloads,
  idempotent subscribe, boundary clear).
- Integration test: `room_meta_update` frames carry `background` only on
  0↔n transitions; session replacement publishes false.
- Restart-gate test: deferral + drain-retry.
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  green from `pi-extension/`.

## Implementation notes

- Landed `BackgroundActivityTracker` with structural `unknown` payload
  narrowing, per-bus idempotent subscriptions, transition-only callbacks,
  session-boundary clearing, and teardown in
  `pi-extension/src/extension/background_activity.ts`.
- Added `RoomMeta.background` and threaded the patch through relay transport
  and the extension composition root. The process-scoped tracker publishes
  background transitions, resets on stop/session replacement, and seeds
  reconnect hello metadata from its current count.
- Hardened the hot-reload gate in `pi-extension/src/index.ts`: active
  background work defers without consuming the armed request, while the
  stored minimal settlement context retries the gate after the tracker drains.
- Added tracker, composition-root, relay-seam, and extension restart-gate
  coverage. Verification: `corepack pnpm typecheck` passed; full Vitest run
  passed with 63 test files and 1,118 passing tests (3 skipped);
  `corepack pnpm build` passed.

## Ordering

First checkpoint — the app-surface story depends on the wire field
landing here.
