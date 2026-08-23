---
id: story-fix-soak-identity-window-submission-drop
kind: story
stage: done
tags: [bug, app]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Preserve submissions raced by reconnect generation changes

## Symptom

The deterministic live soak for seed `20260823` failed with
`identity-window submission disappeared after reconnect` after the scheduled
`net_down`/`net_clear` window. The capture showed reconnect recovery and fresh
envelopes, but no `msgSend`, `sendQueue`, or echo for the probe submitted while
the replacement channel was connecting.

## Root cause

`SyncService.sendMessage()` accepted the submission while a canonical session
was still bound, then awaited its serialized optimistic transcript append. A
connection-status edge incremented `_lifecycleGeneration` while that append was
queued. The generation fence correctly suppressed the stale write, but the
caller then returned on the stale-generation/channel guard without moving the
already-accepted input into the visible held-send path. The W1 fix covered the
case where session identity was absent at method entry, but not identity-present
submissions invalidated during the first asynchronous persistence boundary.

## Fix approach

When the optimistic append is invalidated by a reconnect while the same peer and
room remain selected, retain the original client id and input as a visible held
submission. Serialize its binding through the existing lifecycle lane, persist a
held transition for the canonical session, rematerialize the projection, and
let fresh room confirmation drive the existing reconnect resend path. Do not
carry a raced submission into a different peer, room, or session.

## Regression test

`app/test/data/sync/sync_service_test.dart` blocks one transcript projection read,
queues a second send behind it, changes the connection generation, and releases
the write. It requires the raced submission to remain visible, become exactly
one durable row, and be re-sent with its original intent after same-session room
recovery.

## Failing reproduction

Before the fix:

```text
reconnect generation change cannot swallow a queued submission
  timed out waiting for the reconnect-raced submission to remain visible
```

Command: `flutter test test/data/sync/sync_service_test.dart --plain-name
'reconnect generation change cannot swallow a queued submission'`.

## Implementation notes

- **Diagnosis:** real residual app defect, not an over-strict soak assertion. The
  seed capture's missing `msgSend`/`sendQueue` pair matched the deterministic
  unit interleaving where the queued append is generation-fenced before any
  visible fallback is established.
- **Execution capability:** `sol/high`, selected by the operator because the fix
  crosses reconnect lifecycle fencing, transcript event materialization,
  pending-send timers, and resend idempotency while remaining app-local.
- **Files changed:** `app/lib/data/sync/sync_service.dart`,
  `app/test/data/sync/sync_service_test.dart`, and this story.
- **Fix:** a same-peer/same-room reconnect interruption retains the original
  input and client id in the visible pending lane. Binding writes a distinct
  held transition, rematerializes duplicate-safe durable projection before
  removing the in-memory row, and only binds to the original canonical session.
  Fresh room confirmation then uses the existing held resend path.
- **Regression evidence:** the new explicit-interleaving test failed before the
  fix with `timed out waiting for the reconnect-raced submission to remain
  visible`; it now proves visible retention, one durable row, and reconnect
  resend. The full `sync_service_test.dart` file passes 97 tests.
- **Four-step confirmation:** the targeted test passes; `flutter test
  --exclude-tags e2e --concurrency=2` passes all 887 tests; `flutter analyze`
  reports no issues; exact live soaks `--duration 300 --seed 20260823` and
  `--seed 20260824` both pass with the raced probe logged held, re-sent, echoed,
  and present in matching DB/ViewModel oracle projections. Evidence is retained
  at `.work/session-notes/live-soak-20260823T005633Z-20260823/` and
  `.work/session-notes/live-soak-20260823T010336Z-20260824/`.
- **Generator confidence:** no soak-generator change was needed;
  `python3 -m unittest e2e.test_live_soak` passes all 17 tests. The empty
  `e2e/expected-soak-findings.txt` remains empty: this distinct product defect
  was repaired in-session and is not a still-open expected finding.
- **Device hygiene:** both runner-owned emulator sessions stopped; final cleanup
  removed `app/build`, the Gradle build cache, and disposable `outpost34` AVD
  writable state. The emulator is down and 167G remains free.
- **Adjacent issues parked:** none discovered.

## Bounded inline review

**Verdict: PASS.** Reviewed the focused diff against the failing capture, the W1
visible-pending-or-failed-or-delivered contract, generation-fenced lifecycle
rules, and the pre-existing peer-replacement guard test. Recovery is limited to
the still-selected connection peer and room, session-scoped binding prevents a
late send from crossing session rotation, the original client id drives resend
idempotency, duplicate-safe rematerialization closes both event-store timing
orders, and timers retain bounded failure behavior. The exact failing seed and
a second seed passed without changing the soak assertion or known-findings
manifest. No material blocker or unrelated production change remains. Per the
standalone-story lane, this was an inline self-review with no independent or
cross-model reviewer.
