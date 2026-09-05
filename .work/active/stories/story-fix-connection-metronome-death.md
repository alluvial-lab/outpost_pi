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

## Current diagnosis (instrumentation stride 2026-09-01)

The historic capture cannot identify who closed the socket: the app recorded
only `channelDone`, and the relay did not attribute its close branches. No
behavioral fix is justified from that evidence alone.

Code reading and a real-WebSocket interleaving harness changed the candidate
ranking:

1. **Relay outbound-mailbox saturation is plausible but unproven.** Each
   connection has a 16-frame bounded mailbox
   (`relay/src/resource_limits.rs`); one `try_send(Full)` requests immediate
   disconnect (`relay/src/peers/connections.rs`). That close branch previously
   had no per-connection log. Send-correlated room/working/turn bursts can
   exercise this path, but the old relay capture cannot prove that it did.
2. **Intermediary transport loss remains plausible.** A content-free stream
   error/done with no same-time relay close row will isolate this branch.
3. **The late racing-socket hypothesis is now deprioritized for the exercised
   sequence.** The transport-seam regression opens two real sockets, admits
   the fallback winner, releases the delayed loser's auth handling, and proves
   that the loser was already closed and cannot evict the winner. This does not
   prove every Android lifecycle interleaving safe, but it falsifies the
   leading concrete winner-gets-closed sequence.

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

## Next conclusive repro

1. Deploy the instrumented app and relay together with `RUST_LOG=relay=debug`;
   do not change reconnect timing or mailbox limits.
2. Run the operator loop (open chat, send, leave foreground, wait at least 45s)
   until one loss, then export the app capture and the matching relay log
   window.
3. Classify the first non-stale loss:
   - `closeOrigin=localClose`: `closePath` names the app owner that killed it.
   - `closeOrigin=serverCloseFrame`: use the code/reason-presence category and
     the same-time relay close row.
   - matching relay `close_reason=relay_outbound_mailbox_saturated`: reproduce
     queue pressure and fix the producer/backpressure path, not the capacity by
     guesswork.
   - matching `relay_same_device_superseded`: correlate the new connection's
     auth row and extend the seam harness to that exact lifecycle ordering.
   - `streamDone`/`streamError` with no matching relay-close row: capture the
     Tailscale/docker network path and inspect the close code/error category.
4. Only after one branch is named from that evidence, add the minimal behavior
   fix, rerun the repro, and advance this story to review.

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
- [ ] `flutter analyze && flutter test --exclude-tags e2e` green after the
  final fix; relay checks green if relay remains touched.

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
