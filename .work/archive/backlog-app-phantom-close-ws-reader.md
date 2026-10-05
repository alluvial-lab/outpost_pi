---
id: backlog-app-phantom-close-ws-reader
created: 2026-09-08
updated: 2026-10-05
tags: [app, bug]
status: superseded
superseded_by: story-fix-metronome-phantom-close-teardown
resolved: "2026-10-05 groom: hand-rolled-parser root cause contradicted by metronome investigation; close-attribution correction shipped. Overall connection-death investigation continues in story-fix-connection-metronome-death (active)"
---

# App WS reader synthesizes phantom server-close(1002) under fragmented large frames

THE metronome root cause (verdict #4, story-fix-connection-metronome-death):
the hand-rolled inbound frame parser in ws_transport misparses under
fragmented extended64-length delivery (189KB firehose envelopes) and
reports a server close(1002) the relay never sent, tearing down a healthy
connection. Underlay-independent (5G included). Fix: audit/repair the
inbound framing state machine; add a regression harness that feeds the
firehose envelope split at every socket-read boundary. Pairs with
reader-side backpressure (relay mailbox saturated once during the capture —
relay behaved correctly and logged it).
