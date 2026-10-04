---
id: story-fix-metronome-phantom-close-teardown
kind: story
stage: drafting
tags: [app, bug, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-08
updated: 2026-10-04
---

# Metronome root-cause fix: phantom-close attribution, firehose parse stall, missed-pong teardown

The metronome's full chain (story-fix-connection-metronome-death verdict
#4 + correction, 2026-09-08): fleet firehose bursts (190KB envelopes) stall
the phone's main-isolate inbound parse → TCP backpressure fills the relay's
send path → dart's 45s pingInterval missed-pong watchdog kills the
connection (dart synthesizes closeCode 1002) → the app's close attribution
misreports it as `serverCloseFrame 1002` → cancel race drags recovery.
Relay exonerated; underlay-independent.

## Implementation discovery (2026-10-04) — kill-trigger premise falsified by field evidence; units re-scoped

Verdict #9 (see `story-fix-connection-metronome-death`) paired the v0.12.0
instrument with concurrent relay logs on the production path, 5/5 strikes:
the phone's netstack RSTs the relay's socket 1.56–1.61s BEFORE the app
teardown, the relay never closes and sees no violation, and deaths occur
as fast as 3.8s after online — far inside any 45s pong window. The header
chain above (parse stall → backpressure → **45s missed-pong watchdog
kills**) is therefore falsified as the strike owner; no dart timer fires
before the RST arrives. What survives field evidence:

- **Unit 1 (attribution correction) — CONFIRMED, now field-proven 5/5**: all
  five strikes logged `serverCloseFrame 1002` with the app's own
  `closeInitiated` write into the dead socket and an RST at the relay.
- **Recovery ladder — promoted to primary app-side lever**: the cancel-race
  (`retryConnect _CancelledError` ×8, 10–30s backoffs, ~4min offline) and
  the inbound-dead retry behavior (hello delivered, preauth never seen;
  3s give-up) are the fixable UX surface.
- **Units 2 (parse stall) and 3 (missed-pong liveness)** — demoted to
  resilience/hygiene; neither owns the strike. The dart closeCode probe
  (unit 1's empirical verification) remains worth landing.

Returned to `drafting` for re-design against this evidence; the strike
itself remains phone-netstack (verdict #8 actionables: tailscale-android
bug report with the paired evidence, battery-optimization check,
home-LAN relay / burst-splitting mitigations).

## Fix units

1. **Attribution correction** — `_recordStreamDone` (ws_transport.dart)
   must not classify dart-synthesized closeCode 1002 as
   `serverCloseFrame`. Verify dart:io/IOWebSocketChannel closeCode
   semantics empirically (write the probe test first), then correct the
   heuristic so abnormal teardowns report as streamDone/abnormal with the
   synthesized code preserved for diagnostics.
2. **Firehose parse off the read critical path** — the ws.stream.listen
   callback demuxes/decodes (b64 + utf8 + JSON) on the main isolate;
   190KB envelopes stall socket reads. Move heavy decode off the callback
   (queued/isolate/chunked — match existing app patterns; keep ordering).
3. **Liveness tolerance** — dart `pingInterval: 45s` kills connections
   whose pong is stuck behind backpressure. Replace or widen it with the
   app-level any-inbound-frame liveness the code already documents (see
   the connect-options comment block referencing
   story-mobile-connection-flapping-drops-identity-frames).

## Acceptance evidence

- Probe/regression tests: close-attribution for abnormal teardown reports
  streamDone (+ synthesized code), NOT serverCloseFrame; a firehose-sized
  envelope delivered with simulated slow processing does not stall reads
  nor trigger teardown; missed-pong-under-burst scenario no longer closes
  (or is replaced by the app-level liveness with a test for it).
- `flutter analyze && flutter test --exclude-tags e2e` green (known
  sync_service load-flake: isolation-green bar).
- Live confirmation deferred to operator at rc.2 UAT (5G + home).

## Implementation discovery

The required probes were run before any production change, against Flutter
3.47.1 / Dart 3.13.1 with the resolved `web_socket_channel` 3.0.3:

- Abrupt mid-frame TCP death: `IOWebSocketChannel` surfaced `closeCode ==
  1006` (`WebSocketStatus.abnormalClosure`), with no server Close frame.
- Missed-pong kill: a direct `IOWebSocketChannel` with a 50ms
  `pingInterval`, against a handshake-complete server that never answered
  pings, surfaced `closeCode == 1001` (`WebSocketStatus.goingAway`).
- Framing garbage: a post-handshake reserved opcode (`0x83`) surfaced
  `closeCode == 1002` (`WebSocketStatus.protocolError`).

Therefore the missed-pong leg does not pin the hypothesized 1002, while framing
protocol failure does. The captured `serverCloseFrame 1002` cannot be honestly
attributed to a dart missed-pong kill from close code alone, and the original
VERDICT #4 CORRECTION mechanism remains unconfirmed. Per the land-mode escape
hatch, implementation stopped here: no attribution, decode-queue, or liveness
production changes were made. The story remains `stage: implementing` pending
diagnosis of the captured 1002 path; genuine server-close attribution coverage
remains unchanged.

Pulled into v0.12.0 by operator decision (2026-09-08), then RETURNED to
unbound (same day): the probe map falsified the briefed mechanism twice
(escape hatch used correctly); the fix waits on the paired frame-hash
instrument to settle sender-vs-transit-vs-parser. The instrument rides
rc.2 instead; this story stays active with the open discovery.
