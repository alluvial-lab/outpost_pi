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

## Unknown (the blocking gap)

WHO closes the socket. Both sides see the close nearly simultaneously;
the relay logs nothing at close (INFO+debug level) — no relay-initiated
reason. The app ring records `channelDone` WITHOUT the WebSocket close
code/detail. Candidates, ranked:
1. **Client self-close from racing connection paths** — resume/reconnect
   ladder supersession opening duplicate sockets (the two auth-phase
   failures are racing sockets being rejected); a stale-supersession bug
   could close the WINNER.
2. Intermediary cut (tailscale path / docker port-forward idle) —
   weakened by the send-correlation and 13s median.
3. Relay-initiated close without logging — no evidence, lowest.

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

## Acceptance criteria

- Instrumentation: connChannelLost rows carry close code/reason/origin.
- Root cause named with instrumented evidence (file:line).
- Fix + regression test; `flutter analyze && flutter test --exclude-tags
  e2e` green; relay touched only if the evidence lands there
  (`cargo fmt --check && cargo clippy -- -D warnings && cargo test`).
