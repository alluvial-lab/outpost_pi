# Session note: 2026-07-06 — relay re-inspection corrects Bug 1, refines Bug 2

Picking up from the 2026-07-06 (late) note: both new bugs were at `stage: drafting`
and the next step for Bug 2 was "inspect the relay's current room registry."
The relay is connected on this VM, so I did that read-only inspection now.

## What I did

Live inspection of `remote-pi-relay` (container up since 02:34 UTC, image
`remote-pi-relay:0.2.0`): full auth log, drop-direction tally, and a static
trace of `dispatch_outer` / `room_meta_update` / `RoomManager.subscribe`.

## Bug 1 (send-timeout / `room=main`) — the relay evidence does NOT support the stated mechanism

The story claimed: "the phone's OUTBOUND envelopes carry `room=main`" and the
relay drops them — citing `from=l2X/dUc= dest=MD/tL3E= room=main`. That
directionality is **backwards**:

- `connection_actor.rs:126-167` (`dispatch_outer`): `from` = `self.peer_short`
  (authenticated **sender**), `dest` = `env.peer` (destination), `room` =
  `env.room` (**destination** room). So the cited line is **Pi → phone**, not
  phone → Pi.
- Across the **full relay log** there are **0** `from=MD/tL3E=` (phone-originated)
  drop lines. Every drop is `from=l2X/dUc= dest=MD/tL3E= room=main` — the Pi
  pushing live events to the phone at the phone's OWN room `main` (the phone
  auths with `hello.room_id = 'main'`; `ws_transport.dart:250`). That `room=main`
  is CORRECT; the drop fires only when the phone is offline (no live conn in
  `(MD/tL3E=, main)`). Not a routing bug.
- **Zero relay activity at the 14:42:47 repro second** (only 10s firehose
  metrics). If the phone's envelope had reached the relay and been dropped for
  a room mismatch, there'd be a `from=MD/tL3E=` drop at ~14:42:47. There isn't.
  So the phone's send either never reached the relay (app transport never
  flushed) or reached it and was forwarded but the Pi didn't echo.

Revised the story: the reorder fix (`ca555be`) is still defensible on its own
merits (latent inbound-demux fix) but is **not** the confirmed cause of this
send_timeout. Re-opened: what actually consumed the 14:42:47 send for 20s?
Needs the extension's debug log or a decoded ring-log WS-send event at the
repro instant to distinguish app-transport-stuck vs Pi-didn't-echo.

## Bug 2 (cross-session leak) — relay is structurally innocent; NEW structural fact

Confirmed the `a497ee8` AMBIGUOUS finding: `room_meta_update` keys
`apply_patch` by `(peer_id, room_id)` and drops unknown pairs — a sibling
cannot mutate room `7ADky`'s entry via its own room id. BUT the live log
surfaced a structural fact the prior traces missed:

**All 4 dev-VM Pi processes authenticate under the SAME owner epk `l2X/dUc=`**
(rooms `SF_DCbXsmreE`, `7ADky8889NJy`, `zuMPC-YTtdUD`, `k0H-7lFh371e`). They
share one owner keyring. Consequences:

1. A sibling Pi sending `room_meta_update` for room `7ADky` resolves to key
   `(l2X/dUc=, 7ADky)` — which EXISTS (the 7ADky Pi registered it). So a
   sibling could stamp a new session_id onto the `7ADky` room entry via the
   shared peer_id. **Candidate leak path** — needs checking: does the
   extension ever send `room_meta_update` for a room it did NOT register?
2. `RoomManager.subscribe` is peer-keyed, not room-keyed, so the phone
   receives `room_meta_updated` for all 4 sibling rooms. Delivery-side
   precondition for the h2 leak.
3. The 7ADky Pi did NOT re-auth during 14:40-14:43 (auths at 02:36/03:19,
   next at 17:53). Any session rotation in that window came via
   `room_meta_update`, not reconnect.

Refined the open question: does the extension ever send `room_meta_update`
for a sibling room id? If yes → shared-peer_id path overwrites `7ADky`'s
session_id (h2 leak). If no → rotation is the 7ADky Pi's own (h1, correct).
Needs the extension's debug log or a decoded ring-log `room_meta_updated`
(room + session_id + peer) for the 14:40-14:43 window.

## Not done this session

- Did NOT rebuild/sideload the app or deploy the reorder fix (the story's
  premise for doing so is now undermined — Bug 1's relay-drop mechanism is
  unsupported).
- Did NOT touch the two stage:review stories (reorder, dup); they remain
  ready for a final review pass or release binding.
- Did NOT add relay INFO logging for `room_meta_update` (would help future
  triage; low-cost, worth a small follow-up but not blocking).

## Key files touched
- `.work/active/stories/story-mobile-send-timeout-relay-room-main-mismatch.md`
  — root cause rewritten; acceptance criteria revised; fix path re-opened.
- `.work/active/stories/story-mobile-cross-session-history-leak.md` — new
  structural fact + refined open question added.

## Next steps (priority order)
1. **Bug 1**: capture the extension's debug log at a fresh send_timeout repro
   (or decode the ring-log WS-send event at the repro instant). Decide
   app-transport-stuck vs Pi-didn't-echo. THEN fix.
2. **Bug 2**: check whether the extension sends `room_meta_update` for sibling
   rooms. If yes, that's the leak; if no, it's the 7ADky Pi's own rotation (h1).
3. Optional: add relay INFO logging for `room_meta_update` accept/drop to make
   future cross-session triage possible from relay logs alone.
