---
id: story-fix-connection-metronome-death
kind: story
stage: implementing
tags: [app, bug, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-01
updated: 2026-09-01
---

# Connection dies ~13-35s after connect (worsening); swallows agent turns mid-flap

## Incident (operator report 2026-09-01 + three captures)

A chat swallowed an agent turn while open. Capture
`debug/app-capture-2026-09-01T15-36-13-082Z-466cbb4c4439.bin` (0.11.1
release build, 22h span) shows the underlying disease:

- **Metronomic connection death**: median online→lost = 13.1s (0.11.1)
  vs 34.5s on the Aug-28 capture (0.11.0) — pre-existing and WORSENING.
  Losses cluster 20-70s after msgSend (11/17 within 90s of a send).
- The 15:19 incident end-to-end: msgSend 15:19:39 → echoed → pi woke,
  delivered, TURN RAN (relay `working` heartbeats continue through the
  outage) → app channel died 15:19:53 BEFORE any agent frame arrived →
  app flapped (two relay-side "handshake step failed, closing phase
  auth" at 15:20:28/32 from racing sockets) → rehydrations at 15:20:26
  and 15:21:34 DID deliver large sync envelopes (27.5KB / 23.8KB) but
  connections died 8-14s later each time → turn never rendered for the
  operator (swallowed) → operator retried (sends 15:26, 15:30, 15:33,
  15:34, 15:35 each chased by losses).
- Protocol oracles all PASS (final durable state consistent); triage
  flags 3 anomalous connChannelLost clusters. Message sends always
  echo. The swallow is acquisition-side during the flap.
- pi-side delivery.log healthy throughout (message delivered to the
  NextUp session; turn committed).

## Current diagnosis (frame-order stride 2026-09-05)

The instrumented field capture establishes a server Close(1002) with no prior
app-attributed local close. The relay's only surfaced error is the later
`IO error: Connection reset by peer (os error 104)`: tungstenite consumed the
original violation while auto-closing, so that row cannot identify the bad
header. Relay mailbox saturation, same-device supersession, and an ordinary
network loss do not produce this 1002 shape.

The owning frame is still not named, so no behavioral fix is justified. The
remaining evidence is ranked as follows:

1. **A target-only WebSocket emission failure remains possible.** Every app
   write site passes a `jsonEncode(...)` String to dart:io, which makes invalid
   UTF-8 impossible at the authored seam. The live x86 Android harness captured
   147 additional client frames after this stride: every frame was final,
   masked, RSV-clear, and used a valid TEXT/PONG/CLOSE opcode. The field device
   is ARM Android, so a dart:io/AOT/platform-only header or length failure is
   not excluded.
2. **Frame-boundary corruption below the authored seam remains possible but
   unproven.** A wrong encoded length can make payload bytes look like a later
   reserved/unmasked header. TCP/Tailscale cannot normally reorder or fabricate
   bytes, so this ranks below a target-specific emitter fault.
3. **The app-level Close-race theory is now falsified for the suspected
   sequence.** There are exactly two direct `WebSocketSink.close` sites
   (`app/lib/data/transport/ws_transport.dart:406,697` after this stride), and
   both record the initiating local path before closing. Every manager close
   funnels through `_closeOwned` with a `ChannelLocalClosePath`; both peer
   adapters preserve it. Dart's `_WebSocketConsumer` serializes queued writes
   before Close and drops adds once its controller is closed
   (`websocket_impl.dart:1258-1272`). A raw RFC 6455 regression queued four
   512-KiB sends and immediately closed: all four arrived as legal masked TEXT
   frames before one masked Close, with no DATA afterward. The only SDK-local
   unattributed close is the 45s ping plus 45s pong timeout, incompatible with
   8-35s strikes.

## Fix approach (two strides, instrumentation FIRST)

1. **Instrument**: capture the WebSocket close code + reason (and
   whether close came from the channel's close frame vs stream error vs
   our own supersession logic) in the debug ring's connChannelLost row.
   Also log relay-side close initiations at debug when we are the
   closer. This makes the next repro conclusive.
2. **Diagnose with instrumentation + code reading**: trace
   connection_manager/ws_transport supersession and resume paths for
   the racing-socket shape; fix the winner-gets-closed bug (or
   intermediary finding) with a regression test at the transport seam.
3. Re-run the operator repro loop (send → 30s window) to confirm
   connection stability and turn acquisition.

## Instrumentation delivered

- `WsTransport` records the first close cause: close-frame vs stream error vs
  content-free stream completion vs local close, including WebSocket close
  code, a reason presence/absence category, runtime error type, and the exact
  local lifecycle path.
- `PlainPeerChannel`/`SecurePeerChannel` preserve that evidence through the
  transport seam; `ConnectionManager` writes it into every observed
  `connChannelLost` row as `closeOrigin`, `closeCode`, `closeReason`,
  `closePath`, and optional `errorType`.
- Server reason text is reduced to `present`/`none`; no payload or arbitrary
  exception text enters the debug ring.
- Relay-initiated mailbox saturation, same-device supersession, and Pi-forward
  rate-limit closes now emit structured close-origin/reason rows with
  peer/room/connection attribution.
- Focused local harnesses cover remote close metadata, reason scrubbing,
  local-path attribution, manager-event projection, and the racing-socket
  winner-survival sequence.
- `wsOut` ring rows now record each authored WebSocket write's per-connection
  sequence, fixed write stage, expected first header byte, mask requirement,
  UTF-8 payload length/class, and the exact local Close-initiation path. This is
  an intent-side diagnostic, not a claim about bytes after dart:io encoding.
- `OUTPOST_PI_E2E_RUST_LOG` makes the live relay log filter configurable. Use
  only `tungstenite::protocol::frame::frame=trace,relay=debug`: that narrow
  module logs the two header bytes/opcode/mask before validation and does not
  log payloads. Broad `tungstenite=trace` is forbidden for field capture because
  sibling modules print message content.

## Next conclusive repro

1. Deploy this instrumented app and run the relay with exactly
   `RUST_LOG='relay=debug,tungstenite::protocol::frame::frame=trace'`; do not
   change reconnect timing or mailbox limits and do not enable broader
   tungstenite trace targets.
2. Run the operator loop (connect, switch rooms/replay subscriptions, send,
   leave foreground, wait at least 45s) until one 1002, then export the app
   capture and matching relay header window.
3. Correlate `wsOut.connectionId`/`sequence` with the close timestamp:
   - a `closeInitiated` row before the violation names the exact app owner; an
     actual relay DATA header after the matching Close would revive the race
     theory with a concrete ordering;
   - no prior `closeInitiated` rules out all authored close paths, leaving the
     dart:io/control-frame or below-SDK emitter;
   - the relay's final `Parsed headers [first, second]`, `Opcode`, and `Masked`
     rows name invalid RSV/FIN/opcode/mask/length-class headers without content;
   - legal headers followed by 1002 narrow the fault to frame boundaries or
     payload validation, which must be tested against that exact byte class.
4. Only after the violating frame is named should a minimal behavior fix land.

## Verification (frame-order stride 2026-09-05)

- Focused debug/privacy, real-WebSocket diagnostics, raw RFC 6455 frame-order,
  and capture-site routing tests — pass (32 tests in the combined focused run).
- `flutter analyze` — pass.
- `e2e/run-live.sh state-shapes` with the narrow tungstenite header trace —
  pass: connect → room switches/replays → sends → reconnects; 147 parsed client
  frames, zero invalid headers, zero 1002. The exported ring retained the final
  12 `wsOut` rows, including per-connection Close paths.
- First full test run found the new tag missing from the capture-site registry;
  fixed by naming the production-seam routing test. The next full run reached
  1,013 passes except one unrelated parallel-only
  `chat_viewmodel_test.dart` timing failure; that exact test passed alone.
  Final `flutter test --exclude-tags e2e` rerun — pass, 1,014 tests.

## Verification (instrumentation stride)

- `flutter analyze` — pass.
- `flutter test --exclude-tags e2e` — 1,012 passed.
- `cargo fmt --check && cargo clippy -- -D warnings` — pass.
- `cargo test` — 235 passed across unit/integration suites.

## Acceptance criteria

- [x] Instrumentation: connChannelLost rows carry close
  code/reason/origin/path.
- [ ] Root cause named with instrumented evidence (file:line).
- [ ] Minimal fix confirmed by the operator repro.
- [x] Transport-seam test proves the winning racing socket survives.
- [x] Raw transport-seam test proves queued app DATA is ordered before Close
  and no DATA follows it.
- [x] `flutter analyze && flutter test --exclude-tags e2e` green after this
  final instrumentation stride; relay source remained untouched.

## Linked symptom (operator report 2026-09-05)

TUI-authored user messages occasionally missing on mobile. Mechanism
hypothesis: TUI messages reach the app only via transcript sync/replay
(they never cross app ingress); if the app is mid-flap when one commits,
acquisition depends on the next rehydrate — a replay cursor/high-water
that advances past an unrendered event would skip it permanently.
Prediction: misses correlate with the 1002 flap windows and affect only
TUI-authored user_input. Verify when tracing: pick a known-missed TUI
message (operator timestamps it), confirm it committed to the pi
transcript, then trace which sync/replay windows carried it and whether
the app's cursor skipped past it.

## Linked symptom 2 (operator report 2026-09-05, later same day; sync limit resolved 2026-09-07)

"Earlier history is not synced on this device" notice, first time seen.
Mechanics: full session rehydrations replayed only the last 30 transcript
events (overridable via OUTPOST_PI_SYNC_LIMIT); active multi-day sessions
carry thousands of events, so every full rehydrate reported truncated.
On a stable connection the app hydrates once and rides incremental deltas —
the notice surfacing then was diagnostic of the flap forcing repeated FULL
rehydrations (same root as symptom 1). Follow-up (a) landed 2026-09-07:
SYNC_LIMIT_DEFAULT raised 30 → 200 (sized from measured event-size
distribution vs the 4MiB decoded relay frame ceiling; ~7 busy turns).
Remaining follow-up: (b) confirm the notice returns to its quiet
once-per-attach behavior.

## Network context (operator, 2026-09-05)

Phone runs Tailscale with split tunneling (5G); currently home Wi-Fi.
Either way the tailscale interface is in the path (relay is 100.106.7.70,
CGNAT range — routed through tailscale on every underlay). Implications:
underlay varies while tunnel is constant — underlay likely cleared given
the endpoint-generated 1002 close frame (a tunnel cannot fabricate WS
close frames); tailscale's Android VPN socket-rebind behavior remains a
plausible source of the teardown RSTs but not of the 1002. Open datum:
whether the operator observes strikes on BOTH underlays.

## Verdict (2026-09-06, stride-3 capture)

Adjudication capture app-capture-2026-09-06T15-52-58: two strikes, both
with complete stride-3 evidence. Every outbound INTENT legal (masked
FIN+TEXT, control ~80B + envelope 193B); no local close preceded either
1002 (the 0.0s closeInitiated row is dart's close-handshake ECHO of the
server's frame). The relay's tungstenite rejected bytes the app never
authored. Harness control: same app+relay on a clean path emit only
legal frames (147 captured, zero 1002). CONCLUSION: byte-stream
alteration between the phone's dart layer and the relay — prime suspect
tailscale's Android userspace network stack (constant across underlays,
phone-only, activity-shaped, harness-clean).

## Differential test + mitigation (operator, at home on Wi-Fi)

Point the app at the relay over LAN (direct 192.168.50.x:3300, bypassing
tailscale; relay-failover candidates support this). Strikes stop on LAN
+ resume on tailscale = verdict sealed. Options after: LAN-primary at
home, wss (TLS) hop to convert corruption into clean network errors,
upstream tailscale issue with the full evidence package. Remaining
luxury proof if ever needed: tcpdump on host:3300 during a strike shows
the corrupted frame bytes directly.

## Verdict REVERSAL (2026-09-07 evening capture)

Post-cutover strikes RESUMED (12 × 1002, 16:46–17:14). The 16h silent
window was NOT the docker-proxy cutover — it was the phone AWAY from
home reaching the relay over tailnet subnet routing. Differential:
tailscale path = 16h clean; home Wi-Fi → router → host virtio NIC
(ens18, VM) = strikes within minutes of arriving home. Exonerated:
docker-proxy (not in path), tailscale (the CLEAN leg — WireGuard
integrity-checking), relay, app. Remaining suspects, ordered: host
virtio NIC offload (tso/gso/gro), phone Wi-Fi stack offload, router.
Test in flight: disable host offloads (operator, needs sudo) → strikes
stop = host convicted; continue = phone/router side (next differential:
force phone traffic over tailnet even at home).

## VERDICT #2 (2026-09-08): host virtio offloads EXONERATED — corruption is router↔phone on the home LAN

The 2026-09-07T17:23:47Z ethtool disable was runtime-only and died at the
22:27:16Z VM reboot (container restart anchor; offloads verified back `on`
post-reboot). Relay 0.5.4 instrumented logs give the full strike history
(IO-104 / reset-without-handshake = the phone-strike signature):

| UTC hour | strikes | regime |
|---|---|---|
| 15–16 | 66 | offloads ON (baseline dense) |
| 17 | 8 (6 pre-disable + 2 at 17:26/17:29) | disable @ 17:23:47 |
| 18 | 2 | **offloads OFF** (18:55 only) |
| 19–20 | 48 | **offloads OFF — dense resumption** |
| 21–22:27 | 2 | offloads OFF, quiet |
| 22:27–01:00 | 15+ | offloads restored ON (reboot) |

Decision math: ~54 strikes WITH offloads off (incl. two 20+ strike hours)
vs. the same order post-reboot with them on — offload state made no
difference. Control: all 77 strikes are the phone peer `qQLDCu8=`; zero
from local pis over loopback on the same relay — the relay host process is
exonerated alongside tailscale, docker-proxy, and now virtio offload.
Pattern is bursty (86-min clean gap; quiet hours adjacent to dense ones) —
usage/RF-correlated, not steady-state hardware offload corruption.

Per the pre-registered tree: **strikes continue post-offload → phone Wi-Fi
stack or router.** Next differential (operator): add the tailnet relay URL
as primary/failover candidate in the app (ordered candidates supported) so
at-home traffic rides tailscale; clean ⇒ mitigation = tailnet-first relay
URL and the corrupting element is router/phone Wi-Fi (report upstream
accordingly). No systemd ethtool unit is warranted — offloads are not the
cause; leave them default-on.

## VERDICT #3 (2026-09-08): strikes ride INSIDE the tailnet tunnel — wire-corruption theory mechanically dead; phone-side tunnel/socket lifecycle is the new prime suspect

Capture `app-capture-2026-09-08T01-16-29-989Z` (13-min window, 1MiB buffer
exhausted by active multi-room streaming — retention item parked) +
relay 0.5.4 logs, cross-aligned:

- **Both-side strike alignment**: relay IO-104 @ 01:13:39.879Z ↔ app
  `retrying` @ 01:13:40.2Z — same event, both instruments agree.
- **Recovery loop is a SECOND, distinct bug (client-side)**: after the
  strike, the app logged 4 `connecting` states + 3 `retryConnect`
  `_CancelledError`s (durations 23s / 103s / 10s — not a fixed timeout;
  cancellations) across 01:13:40→01:16:11, while the relay saw ZERO auth
  attempts in that gap. Connects were cancelled before reaching the wire —
  an app-internal race (something cancels in-flight connects; note the
  attempt counter repeated "attempt 2" twice → overlapping retry
  schedulers suspected). This extends the outage ~2.5 min after every
  strike it follows.
- **Phone is ALWAYS tailnet-sourced**: 23/23 post-reboot phone auths from
  100.121.111.25 (CGNAT). The at-home differential has therefore been
  running de facto — and strikes persist INSIDE the WireGuard tunnel.
- **Mechanism consequence**: WG's poly1305 auth makes underlay byte
  corruption (router or radio) unable to surface as corrupt/truncated TCP
  payload — corrupt packets drop + retransmit, they never deliver bad
  bytes. The "LAN corrupts frames" theory (verdicts #1–2 framing) cannot
  explain the observations. Replacement hypothesis: **Android Wi-Fi
  underlay events (power-save, roam, band steering) make the tailscale
  Android VPN recycle its tunnel, resetting the TCP riding it** — phone
  resets TCP, relay frames legal, only the phone strikes, 16h clean on 5G,
  bursty at home. All prior evidence fits unchanged.
- **Next differential (operator, in progress)**: 5G-at-home (Wi-Fi off an
  hour at home). Clean ⇒ Wi-Fi-underlay↔tunnel interaction confirmed as
  trigger; mitigation is phone-side (tailscale/keepalive/Wi-Fi power-save
  exemption), NOT app protocol. 5G-at-home striking too would widen
  suspicion to the tailscale app itself regardless of underlay.
