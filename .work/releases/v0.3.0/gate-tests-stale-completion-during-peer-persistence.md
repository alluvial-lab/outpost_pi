---
id: gate-tests-stale-completion-during-peer-persistence
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# Stale pairing completion during savePairedPeer await is unfenced and untested

## Priority
High

## Value evidence
Item: `gate-refactor-lifecycle-pairing-viewmodel-no-dispose` says a stale
successful handshake cannot persist, adopt, or emit. The stale-completion
test invalidates before `performPairing` returns; it does not cover
invalidation while `savePairedPeer` itself is awaiting. Current code can
finish that durable write after retry/dispose before noticing the stale
generation.

## Gap type
complex-unit

## Suggested test
Gate `savePairedPeer` with completers. Let the handshake succeed and
persistence start, then call `retry()` and separately `dispose()`. Release
persistence and assert no durable peer remains, the transient transport
closes, no channel is adopted, and no paired/error state is emitted. If the
test proves the durable write lands post-invalidation, fence the write
itself (re-check generation immediately before persisting) as part of this
item.

## Test location (suggested)
`app/test/ui/pairing/pairing_viewmodel_test.dart`

## Absorbed refactor finding (2026-07-24 drain-delta refactor gate)

`lifecycle/resource-no-dispose` (High) at `pairing_viewmodel.dart:125`: the
generation is checked before `savePairedPeer`, but the asynchronous durable
write can complete after `retry()`/`dispose()` invalidates the attempt, and
the stale continuation then closes mutable GLOBAL transient fields via
`_closeTransient()` — which may belong to a NEWER attempt. Fix direction
(merged into this item's scope): bind persistence and transient resources to
the initiating generation; gate the serialized write at commit time and
close captured attempt-local resources, not the ViewModel's current fields.

## Implementation notes

- Added `PairingStorage.savePairedPeerIfCurrent`, which evaluates the
  generation predicate inside the serialized mutation turn immediately before
  durable peer creation.
- Replaced mutable-global transient teardown with generation-local
  `_PairingAttempt` ownership; stale retry/dispose continuations only close
  their captured transport/channel.
- Added completer-gated retry and dispose tests while persistence is pending;
  both prove no peer write, adoption, paired/error emission, or cross-attempt
  resource closure. Verification: `flutter test
  test/ui/pairing/pairing_viewmodel_test.dart` passed (12 tests).

## Review

Bounded inline review (orchestrator, 2026-07-24): diffs inspected against
acceptance — SHA-256 owner-state fingerprint initialized once, compared
before every boot acceptance, updated only on committed cleanup; real-bridge
failure-path tests assert marker retention + gated identity + exactly-once
commit; pairing attempts now own attempt-local resources with a commit-time
stillCurrent fence. Orchestrator-verified: flutter analyze clean, full
non-e2e suite 847/847 green. Approved -> done.
