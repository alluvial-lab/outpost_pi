---
id: story-add-transport-frame-observability
kind: story
stage: done
review_addressed: 2026-07-05
tags: [app, observability]
parent: feature-cross-side-observability
depends_on: [story-app-debug-log-adapter, story-app-capture-routing]
release_binding: v0.1.0
gate_origin: null
created: 2026-06-28
updated: 2026-07-05
---

# Transport-frame observability: peer-channel silent drops (Unit 6)

## Scope (revised 2026-07-05 after the capture-routing story shipped)

**This story collapsed to a small delta** after `story-app-capture-routing`
(Unit 4) shipped. The original drafting brief imagined a broad design task
spanning app + relay + pi-extension; the realized capture surface is narrower
because much of it is already done:

### Already observable (DO NOT re-implement)
- **App relay-frame drops** (`ws_transport.dart`): the `ws-in` demux branches —
  `dropMissingRoom`, `dropRoomMismatch`, `control` (accepted),
  `dropMalformed` (malformed/decode-failure) — are captured as `WsInEvent`s
  with privacy-safe fields (`bytes`, `kind`, `stage`, `senderRoom`,
  `controlType`, `error`; NO payloads). Debug-gated, with routing tests.
  Shipped in `story-app-capture-routing` (commit d7bc84a).
- **Relay malformed handling**: `handle_malformed_pi_envelope` sends a
  `bad_envelope` transport_error back to the sender (already visible), and
  the relay file-logging story (`story-relay-retroactive-file-logging`)
  shipped a `debug!` on the forward path with `env_id_tail` correlation.
- **Relay-unknown-type / decode-boundary rejections**: the relay rejects
  unknown variants at the generated Serde boundary (visible as transport
  errors + `debug!`), so no separate observability is needed there.

### The remaining gap (THIS story)
**`app/lib/data/transport/peer_channel.dart` has TWO silent-drop sites** with
no `DebugLog` capture:

1. `UnsupportedTypeException` (line ~105): forward-compat — surfaces unknown
   server types as an `ErrorMessage` to the UI, but does NOT log to the ring.
   So a future-incompatible frame type is invisible in retroactive dumps.
2. catch-all `catch (_) { /* Malformed frame — drop silently */ }`
   (line ~116): the comment explicitly says "drop silently" and that previous
   diagnostic logging was removed. This is the exact blind spot the ring log
   exists to close — a malformed peer-channel frame vanishes with no trace.

`PeerChannel` has no `DebugLog` injection today. This story:
- Injects `DebugLog?` into `PeerChannel` (same nullable-in-tests pattern as
  `WsTransport`/`SyncService`/`ConnectionManager`).
- Adds a `DebugTag.peerFrame` variant + a `PeerFrameEvent` to the
  `DebugEvent` registry (Unit 1's typed surface is the extension point).
- Emits at both drop sites with privacy-safe fields (`kind` ∈
  {`unsupported_type`, `malformed`}, `bytes`, `error?`; NO payload/message body).
- Wires production `PeerChannel` construction in `dependencies.dart` to
  receive `_injector.get<DebugLog>()`.
- Adds routing tests (fake `DebugLog`) for both branches + a registry entry.

## Privacy constraints (unchanged from original brief)
- NO payloads, keys, image data, or message bodies in any frame-drop event.
- Capture is debug-gated (the app-global `Preferences.debugLogging` toggle
  from Unit 3 gates the whole ring).
- Throttling: peer-channel drops are not in a hot loop (one per dropped
  frame, which is itself an anomaly), so no explicit throttle is needed
  beyond the ring's 1 MiB cap. If a drop storm ever evicts too fast, the
  cap + per-field length limits already protect the window.

## Acceptance Criteria
- [ ] `DebugTag.peerFrame` + `PeerFrameEvent` added to the registry
      (`app/lib/domain/contracts/debug_log.dart`), with the registry's
      exhaustiveness switch + allow/deny-list updated.
- [ ] `PeerChannel` accepts an optional `DebugLog?` and emits
      `PeerFrameEvent` at BOTH silent-drop sites (unsupported_type + malformed).
- [ ] No payload/message body/key/image data in any `PeerFrameEvent` field.
- [ ] Production `PeerChannel` wiring in `dependencies.dart` passes
      `_injector.get<DebugLog>()`.
- [ ] A fake-`DebugLog` test asserts the `unsupported_type` event fires on
      an `UnsupportedTypeException` and the `malformed` event fires on a
      decode failure — and that neither carries payload data.
- [ ] The registry-exhaustiveness test (`debug_capture_routing_test.dart`)
      gains a `peerFrame` site entry so a silently-stopped emitter is caught.
- [ ] `flutter analyze` clean; `flutter test` green.

## Out of scope
- Re-implementing the `ws-in` relay-frame observability (done in Unit 4).
- Relay-side malformed observability (done: transport_error + `debug!`).
- pi-extension frame observability (the extension side is already
  retroactively diagnosable via `audit.jsonl`; not a ring-log concern).

## References
- Parent: `feature-cross-side-observability.md` (Unit 6).
- Sibling (done): `story-app-capture-routing.md` (Unit 4 — shipped the `ws-in`
  surface this story originally included).
- `app/lib/data/transport/peer_channel.dart:101-120` — the two drop sites.
- `app/lib/domain/contracts/debug_log.dart` — the `DebugEvent` registry to extend.
- `app/lib/config/dependencies.dart` — `PeerChannel` wiring (verify where it's
  constructed; inject `DebugLog` the same way as `WsTransport`).

## Implementation notes

- `app/lib/domain/contracts/debug_log.dart`: added `DebugTag.peerFrame` and `PeerFrameEvent {kind, bytes, error?}` with capped string serialization and no payload-like fields.
- `app/test/domain/contracts/debug_log_test.dart`: extended the registry exhaustiveness switch, variant fixture, and allow-list for `PeerFrameEvent`; deny-list remains unchanged and rejects `body`/`image`/`data`/`args`/`result`/`prompt`/`message`/`ct`.
- `app/lib/data/transport/peer_channel.dart`: added optional `DebugLog?` injection and logs `PeerFrameEvent(kind: 'unsupported_type')` for `UnsupportedTypeException` and `PeerFrameEvent(kind: 'malformed')` with a short scrubbed error type for malformed-frame drops. Existing `ErrorMessage` surfacing and malformed silent-drop behavior are unchanged.
- `app/lib/config/dependencies.dart`: production `PlainPeerChannel` construction in the reconnect factory now passes `_injector.get<DebugLog>()`; `PairingViewModel` registration also passes `DebugLog` so the post-pair adopted `PlainPeerChannel` has the same production observability.
- `app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart`: accepts optional `DebugLog?` and passes it into the post-pair `PlainPeerChannel`; tests remain source-compatible because the parameter is named/optional.
- `app/test/data/debug/debug_capture_routing_test.dart`: added fake-transport routing tests for unsupported-type and malformed peer-channel frames, asserting `bytes`/`kind`, scrubbed/short `error`, and no payload-like keys; added `peerFrame` entries to `requiredSites`.

Verification from `app/` with `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache`:

```text
../.tools/flutter/bin/flutter test test/domain/contracts/debug_log_test.dart test/data/debug/debug_capture_routing_test.dart test/ui/pairing/pairing_viewmodel_test.dart
00:01 +29: All tests passed!

../.tools/flutter/bin/flutter test
00:29 +661: All tests passed!

../.tools/flutter/bin/flutter analyze
Analyzing app...

   info • 'axisAlignment' is deprecated and shouldn't be used. Use alignment instead. This property provides full control over both axes, which is an improvement over the old axisAlignment. This feature was deprecated after v3.41.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/ui/chat/widgets/input_bar.dart:802:7 • deprecated_member_use

1 issue found. (ran in 3.7s)
Command exited with code 1
```

Deviation: `flutter analyze` is not clean because of the pre-existing `axisAlignment` deprecation in `app/lib/ui/chat/widgets/input_bar.dart:802`, which `app/CLAUDE.md` explicitly records as unrelated/pre-existing and the local code comment says not to "fix" without bumping the Flutter pin. This story did not change that file.
