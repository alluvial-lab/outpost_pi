---
id: idea-mobile-new-session-red-timeout-affordance
kind: idea
stage: backlog
tags: [app, bug, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# Brief red "timeout" shown when pressing "New session" itself

## Observed

Live verification of `feature-replacement-session-wake-confirmation`
(2026-07-22, capture `debug/591-11f1-9656-5799420aa9fe.bin`) noted the
operator still sees a brief red "timeout" indicator when pressing "New
session" in the mobile app. This is a DIFFERENT symptom class from the
post-`/new` message bug fixed there:

- **No `msgFailed` is logged** for the `/new` command — it does not travel
  the `msgSend`/`msgEcho`/`msgFailed` channel.
- The session replacement itself converges in ~1s (`room_ended` →
  `room_announced`), so it is not an actual replacement failure.

## Hypothesis (unconfirmed)

An app-side UI affordance on the `/new` command frame (or its action reply)
shows a transient timeout state — either a short action-reply wait that
displays an error style before the reply lands, or the `/new` frame brushing
the same echo-wait surface as user messages. Recorded in
`feature-replacement-session-wake-confirmation` ("Remaining") and noted as
possibly related to `story-mobile-send-timeout-relay-room-main-mismatch`.

## Next

On the next phone session with a ring log: press "New session", capture the
frame path for the command, and identify which UI state shows the red
indicator and what times it out. Then decide: suppress the transient error
style for action frames, or lengthen/separate the action-reply wait.
