---
id: story-app-reattempt-held-pending-on-reconnect
kind: story
stage: drafting
tags: [app, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-13
updated: 2026-07-13
follow_up_of: story-app-half-open-socket-swallows-sends-arrives-late
---

# Re-attempt held-pending (option-1) messages on reconnect (half-open fix, option 4)

## Brief

Direct follow-up to `story-app-half-open-socket-swallows-sends-arrives-late`
(option 1, shipped `6d64556`). Option 1 gates `sendMessage` on room liveness
(`_conn.isRoomLive`): when the room is offline (3 missed pongs or `RoomEnded`),
the message is **held pending** — an optimistic row is written and the
`send_timeout` is armed, but the message is NOT written to the channel. The
option-1 comment says this "fails visibly (or re-attempts on the next healthy
connection)" — but the **re-attempt half was never implemented.** The held-pending
message just fails at `send_timeout` and stays failed.

Option 4 closes that gap: on reconnect, re-send held-pending messages that
were never delivered, so they actually reach the Pi instead of leaving a
permanent failure badge.

## Why this is NOT redundant (unlike options 2 and 3)

The option-2 and option-3 investigations (parked in
`.work/backlog/story-app-teardown-socket-on-send-timeout.md`) found that
option 1 + the existing **late-confirmation** path already fix the user symptom
for messages that *landed*: a timed-out message that reached the Pi gets
reconciled `failed → confirmed` on reconnect via `requestSync` → `SessionHistory`
→ `UserInputEvt` → `UserMessageConfirmed` (`session_history_replay.dart:51`,
`transcript_projection.dart:161-175,252`).

But late-confirmation **only works if the message reached the Pi.** A message
held pending by option 1 was **never sent** (the room was offline, the channel
write was skipped). The Pi doesn't have it, so `SessionHistory` won't include
it, so it can't be confirmed. The row stays `failed` permanently — even though
re-sending it on the next healthy connection would deliver it. **This is the
narrow gap option 4 addresses**, and late-confirmation cannot cover it.

## The gap, precisely

| Message path | Sent to Pi? | On reconnect | Outcome |
|---|---|---|---|
| Sent into live socket, timed out (option 2's window) | Yes (bytes in buffer) | flushes late → `SessionHistory` confirms | ✅ late-confirmation handles it |
| Held pending by option 1 (room offline) | **No** (never written) | `SessionHistory` doesn't include it | ❌ stays `failed` — **the gap** |
| Sent, delivered, echoed normally | Yes | n/a | ✅ confirmed |

## Design (to lock in during the design pass)

### Where the re-send hooks in

`_onlineActivated` (`sync_service.dart:612`) fires on every `StatusOnline`
transition (reconnect). It currently schedules `requestSync` (the
`SessionHistory` pull) but does NOT re-send held-pending/failed messages.
Option 4 adds: on reconnect, re-send any rows that are still `pending` (held
by option 1 and not yet timed out) OR `failed` (timed out while held pending).

The seam: `SyncService` already has the message text/id in the transcript
store. On reconnect, enumerate pending/failed user rows for the active
session and re-send them via the same `sendMessage` path (which now goes
through option 1's gate — if the room is live on the fresh connection, it
proceeds; if still offline, it's held again).

### Dedupe safety (the key design question)

Re-sending a message that *did* somehow land (race window: bytes flushed
just before the room was marked offline, or a duplicate reconnect) would
duplicate it. The dedupe contract is by `clientMessageId` (the `id`):
- The Pi/extension echo path dedupes by `id` (`_recordUserInputEcho`,
  `sync_service.dart` — "Echo dedupes against the optimistic row (same id)").
- `SessionHistory` replay dedupes by `id` (`UserInputEvt.id` →
  `UserMessageConfirmed` with the same `clientMessageId` → projection collapses
  to one row).

So a duplicate send is safe: if the message already landed, the echo/replay
dedupes it; if it didn't land, the re-send delivers it. **But this must be
verified in the design pass** — the dedupe is load-bearing, and a re-send
that produces two visible rows would be a regression.

### What NOT to do

- Do **not** re-send messages that were sent into a live socket and timed out
  (option 2's window). Those landed (or will land on flush) and late-confirmation
  handles them. Re-sending only helps the held-pending case (never sent).
  Distinguishing "held pending, never sent" from "sent, timed out" requires
  tracking whether the channel write happened — the option-1 guard's
  `MsgSendEvent(blocked: true)` debug log is a signal, but the row itself
  doesn't record it. The design must decide how to distinguish (e.g. a
  `held: true` flag on the row, or re-send only `pending` rows that are
  still pending at reconnect time — a `failed` row could be either case).
- Do **not** re-send indefinitely. Cap re-attempts (e.g. once, or within a
  window) so a persistently-unreachable Pi doesn't loop re-sends on every
  reconnect.

### Test plan

- A held-pending message (option 1 path: room offline → held → `send_timeout`
  fires → `failed`) → reconnect → assert the message is re-sent and confirmed.
- A message that was sent into a live socket and timed out → reconnect →
  assert it is NOT re-sent (late-confirmation handles it) — or if re-sent,
  assert dedupe collapses it to one row.
- A held-pending message re-sent on reconnect when the room is STILL offline
  → assert it's held again (not spammed).

## Acceptance

- A message held pending by option 1 (room offline, never sent) that times
  out is re-sent on the next healthy reconnect and delivered (row flips
  `failed → confirmed`), rather than staying permanently failed.
- Re-sending is dedupe-safe: a message that did land is not duplicated
  (echo/replay collapses it to one row).
- Re-attempts are bounded (no infinite re-send loop on a persistently-
  unreachable Pi).
- Tests cover the held-pending re-send, the dedupe case, and the
  still-offline case.

## Out of scope

- Option 2 (tear down on `send_timeout`) — parked; premise disproven.
- Option 3 (tighten WS `pingInterval`) — would reintroduce the connection-
  flapping storm (`story-mobile-connection-flapping-drops-identity-frames`);
  the 45s is a deliberate fix, not a tuning knob. Not pursuing.
- Re-evaluating the Plan-18 decoupling (the more promising follow-up from
  the option-2 analysis) — separate story.

## References

- `app/lib/data/sync/sync_service.dart:296-316` — option 1's held-pending
  guard (the "re-attempts on the next healthy connection" aspiration).
- `app/lib/data/sync/sync_service.dart:612` — `_onlineActivated` (the
  reconnect hook point; currently only `requestSync`, no re-send).
- `app/lib/data/sync/sync_service.dart:523` — `requestSync` (the
  `SessionHistory` pull that handles the "landed" case).
- `app/lib/data/sync/session_history_replay.dart:51` — `UserInputEvt` →
  `UserMessageConfirmed` (late-confirmation; only works if the Pi has the msg).
- `app/lib/domain/transcript/transcript_projection.dart:161-175,252` —
  confirmed-wins-over-failed projection (the dedupe contract).
- `.work/backlog/story-app-teardown-socket-on-send-timeout.md` — option 2
  analysis (parked); documents why options 2/3 are redundant.
- `story-app-half-open-socket-swallows-sends-arrives-late.md` — option 1
  (shipped); options 2–4 filed in its body.
