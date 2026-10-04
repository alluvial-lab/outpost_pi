---
id: story-fix-metronome-phantom-close-teardown
kind: story
stage: review
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-08
updated: 2026-10-04
---

# Close-attribution correction: dart-synthesized 1002 must not report as serverCloseFrame

## Brief

Re-scoped 2026-10-04 after verdict #9 (see
`story-fix-connection-metronome-death`): the v0.12.0 instrument paired with
relay logs proved, 5/5 production strikes, that `connChannelLost` reports
`closeOrigin:"serverCloseFrame" closeCode:1002` while the relay never sent a
close — the phone's netstack RST'd the socket 1.56–1.61s earlier and the app
wrote its own close frame into the dead socket at teardown. The
`serverCloseFrame` classification is dart-synthesized misattribution in
`WsTransport._recordStreamDone` (`app/lib/data/transport/ws_transport.dart`):
it treats ANY closeCode other than 1005 (noStatusReceived) / 1006
(abnormalClosure) as a remote close frame, and dart:io surfaces 1002 on
abnormal teardown paths.

Honest attribution matters beyond diagnostics: failure classification feeds
`classifyWsTransportFailure` → `ReachabilityFailureKind` → the retry ladder,
and future evidence captures must distinguish "relay closed" from "path died".

Former units 2 (firehose parse off critical path) and 3 (missed-pong
liveness) were demoted by verdict #9 — neither owns the strike. The recovery
ladder moved to `story-fix-post-strike-recovery-ladder`.

## Design

**Probe first (test-first, per the original unit 1).** Add an in-process
probe test (`HttpServer` + `WebSocketTransformer` + real
`IOWebSocketChannel` client) that pins dart:io closeCode/closeReason
semantics empirically:

1. server sends a real close frame (1000 with reason; 1002 with/without
   reason) — client `closeCode`/`closeReason`;
2. server destroys the raw socket (RST-like) without a close frame;
3. server closes TCP cleanly (EOF) without a close frame;
4. local `sink.close()` initiated, then socket dies before reply;
5. `pingInterval` expiry with a silent server.

The fix is derived from what the probe shows: `_recordStreamDone` may claim
`serverCloseFrame` ONLY for codes the probe proves are frame-delivered;
dart-synthesized codes observed on dead-path scenarios report as
`streamDone`/`streamError` with the code preserved for diagnostics. If the
probe shows real and synthesized 1002 are indistinguishable at this layer,
the discriminator becomes local-close ordering instead (see next point) and
the probe result is recorded in the story body.

**Local-close ordering audit.** `closeWithPath` and `closeConnectResources`
already call `_recordLocalClose` before `_logCloseInitiated`; verify the
established-channel teardown path (stream done → cleanup → sink.close) cannot
classify a post-local-close teardown as `serverCloseFrame`, and that the
recorded details preserve the first honest classification (`??=` semantics).

## Acceptance

- Probe test lands and documents (in-code) which closeCodes dart:io delivers
  from real frames vs synthesizes on dead paths.
- Regression: the strike shape (no local close recorded, dart closeCode 1002,
  no reason) reports origin `streamDone` (or `streamError`) — NOT
  `serverCloseFrame`; closeCode 1002 preserved in the event.
- Genuine server close frames (probe scenario 1) still report
  `serverCloseFrame` with code+reason.
- `flutter analyze` + `flutter test --exclude-tags e2e` green.

## Verification evidence

Implemented 2026-10-04 over `3af572be7`:

- Probe verdicts (existing suite + new e2e regression): dart:io delivers
  real server Close frames with code+reason (4001 test); it SYNTHESIZES
  1002 on locally-detected framing violations (garbage probe), 1001 on the
  missed-pong watchdog, 1006 on mid-frame death. The relay only closes with
  4xxx codes + reasons or an empty Close — never 1xxx — so both synthesized
  codes are now excluded from `serverCloseFrame` classification in
  `_recordStreamDone` (`ws_transport.dart`): they report origin
  `streamError` with `errorType` `dartProtocolError` / `dartPingWatchdog`,
  closeCode preserved. Revisit condition documented inline: if the relay
  ever starts closing with 1xxx codes, the classification must change.
- Local-close ordering audit: `closeWithPath` / `closeConnectResources`
  already record `localClose` before the close write; `??=` keeps the first
  honest classification. No change needed.
- New regression test 'dart-synthesized protocolError close is not attributed
  to the server' fails on the old heuristic (verified red-first) and pins
  the strike shape end-to-end through `WsTransport`.
- `flutter analyze` clean; full suite `flutter test --exclude-tags e2e
  --concurrency=2`: **1,072 passed** (includes the 10-test close-diagnostics
  suite).
