---
id: story-harvest-app-session-robustness-ports
kind: story
stage: done
tags: [app, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-16
---

# App session robustness ports: reconnect room preservation + iOS onboarding gate

Two small upstream fixes verified in our tree.

## 1. Same-peer reconnect must not clobber room selection — upstream `c7105191`

`app/lib/data/transport/connection_manager.dart:575-586`: the connect path
unconditionally resets `_activePeer`, clears `_activeRoomExplicitlySet`, and
rebinds the room from the (possibly stale) persisted `PeerRecord`. A retry
against the SAME peer after a transient drop can therefore reroute sync/sends
away from the user's explicit room choice. Upstream detects same-peer
reconnect at their `connection_manager.dart:499-508` and preserves selection.
Port: on reconnect where `peer == _activePeer`, keep the explicit-selection
flag and current room. Note our explicit-selection latch
(`:138-141`, set in `switchRoom` `:288-299`, honored at `:1253-1260`) is the
mechanism to protect — the reset at `:576` defeats it.

## 2. iOS onboarding must not hard-gate on the ubiquity token — upstream `535a5a0e`

`app/lib/pairing/owner_identity_bridge.dart:83-85`: `boot()` returns
`SyncUnavailableResult()` whenever `_store.isSyncAvailable()` is false. On an
entitlement-less iOS build (no iCloud capability) the ubiquity token is
*permanently* nil (`app/packages/outpost_pi_identity/ios/Classes/
KeychainSyncStore.swift:84-85`), so onboarding is blocked forever —
indistinguishable from a transient sync outage, which the gate legitimately
covers (per the dartdoc at `:78-80`). Upstream removed the preflight gate and
probes Keychain directly. Port: distinguish "no entitlement" (proceed with
local-only identity, surfaced in UI) from "transient outage" (keep gateable),
preserving the durable-owner fingerprint comparison below.

## Verification

`flutter analyze && flutter test --exclude-tags e2e`; unit tests: same-peer
reconnect preserves explicit room; entitlement-less platform channel returns
proceed-not-block. Cite upstream shas in the commit message.

## Implementation

- Ported same-peer retry preservation into `ConnectionManager`: reconnects keep
  the live room, explicit-selection latch, and an aligned active peer record;
  new-peer connections still bind from persisted metadata.
- Replaced the iOS ubiquity-token check with a synchronizable-Keychain probe and
  made `OwnerIdentityBridge.boot()` trust the real load/save capability path.
  `SyncUnavailable` remains a typed onboarding gate, and durable Owner
  fingerprint/transition checks remain unchanged.
- Added regressions in `app/test/transport/connection_manager_test.dart` and
  `app/test/pairing/owner_identity_bridge_test.dart`.
- Verification: `flutter analyze` passed; both focused test files passed (57
  tests). The prescribed full parallel suite exposed four unrelated isolation
  failures; three passed individually. A serialized rerun still exposed the
  pre-existing sync/debug isolation-timing failures in
  `debug_capture_routing_test.dart` and `debug_log_impl_test.dart`; no unrelated
  test or product code was changed.
