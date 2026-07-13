# Session note — 2026-07-13 (half-open socket diagnosis + fix)

## Goal

Investigate the app-side "failed sends from mobile, message arrives minutes
late" symptom the operator reported, and fix it. The session started from a
live pairing + mobile test message and ended with a proven root cause and a
shipped fix for one of two bugs found.

## What shipped (1 fix, reviewed + committed)

### `story-app-half-open-socket-swallows-sends-arrives-late` (done, `6d64556`)

**Symptom.** The phone sends a message; the app's 20s echo timeout fires
(`send_timeout`, "no echo in 20s") and the user sees a failure — then the
message arrives at the PC **minutes later**, injected into a running turn
(`steer:true`). Two messages sent into the same dead socket arrive together
on a single reconnect, long after both were declared failed.

**Root cause (proven across three sides — ring `e4f-11f1` + relay log +
`delivery.log`).** A **decoupling gap**, not a reset bug. The app deliberately
decouples Pi-liveness (3 missed protocol Pongs → `_markActiveRoomOffline`,
room tile goes grey) from WS-liveness (don't tear down on missed pongs, to
avoid `room_already_open` reconnect failures — the Plan-18 fix). But the send
path trusted `StatusOnline` and nothing connected "3 missed pongs" to "stop
sending into this socket." The app kept accepting `msgSend` into a socket it
had already proven was not reaching the Pi — the bytes sat in the dead send
buffer and flushed on the next reconnect, minutes late.

Dispositive evidence: test 4 sent `00:08:10`, `send_timeout` at `00:08:30`,
arrived PC `00:11:54` (3m44s late); test 5 sent `00:10:19`, `send_timeout` at
`00:10:39`, arrived PC `00:11:54` (1m35s late) — **both arrived within 6ms of
each other** on one reconnect flush. The `ping_missed_room_offline` signal
fired at `00:09:15` (75s after the send) — too late for the 20s echo window,
and it only marked the room offline locally without tearing down the WS.

**Fix (option 1 of 4).** Gate `sendMessage` on `_conn.isRoomLive(epk, roomId)`
in `app/lib/data/sync/sync_service.dart`, after the existing `_conn.channel`
non-null check. When the active room is not live (3 missed pongs or a
`RoomEnded` push), the message takes the same held-pending path as the offline
branch (writes optimistic row, arms send-timeout, returns without writing to
the channel) instead of vanishing into the dead buffer. No new liveness signal
needed — `ConnectionManager.isRoomLive` already returns false after
`_markActiveRoomOffline`.

**Test.** `test (i) half-open socket: room marked offline holds the send
pending` in `sync_service_test.dart`. `_FakeChannel` extended to implement
`IControlLink` so `RoomEnded` can drive the half-open state. TDD-verified
(fails without the fix: message sent into dead socket; passes with it). Full
app suite **684/684 green**; analyzer clean.

**Review.** Fast-lane (story item), Approve, no blockers. One nit recorded
(guard runs after the optimistic row is written — intentional, matches the
offline branch). Process note in the story: the fix was implemented inline
rather than routed through the `fix` skill; the review pass corrected the
stage gap.

### A pre-existing test fragility fixed along the way

Adding the new test exposed a latent timing bug in `canonical room-metadata
session rotation triggers session_sync` (last in the sync suite): its
`2×_settle()` (60ms) was too tight for the 50ms debounced rooms-emit →
`requestSync` path. Bumped to `4×_settle()` (120ms). Bisect showed even a
trivial `setup()+dispose()` test broke it — a pre-existing fragility, not a
regression from the fix.

## What did NOT ship (open follow-ups)

### `story-extension-stale-sibling-evict-on-owner-revocation` (drafting, committed)

The **other** bug found during the same capture window: the PC's cross-PC
agent-mesh transport keeps spamming `pi_envelope` to the **old, revoked**
sibling epk (`l2X/dUc=`) every ~2 min, each rejected `not_authorized` by the
relay. After re-pairing under a new Owner, the in-memory peer list + delivery
queue aren't evicted. Root cause confirmed; not yet implemented. A full pi
restart clears it (workaround). Distinct from `relay-revocation-cache-window`
(relay-side) and `story-to-room-sender-side-room-targeting` (sender `to_room`).

### Half-open story options 2–4 (filed in the story body)

- **Option 2** (most consequential) — tear down the socket on `send_timeout`.
  Closes the window *before* 3 missed pongs fire (test 4: sent `00:08:10`,
  room-offline didn't fire until `00:09:15`). The 20s echo timeout is itself a
  dead-socket signal and should force a reconnect.
- **Option 3** — tighten WS `pingInterval` 45s→15–20s (secondary).
- **Option 4** — re-attempt timed-out messages on reconnect (UX safety net).

## Investigation trail (what got wrong before it got right)

1. **First static trace** hypothesized a backoff-reset-on-frame mechanism
   (`onAppFrameObserved` resets `_retryAttempt` on any inbound frame → 1s
   reconnects racing teardown). Filed as `story-app-ws-churn-10-50s-reconnect-loop`.
2. **First ring capture** (`e46-11f1`, 2026-07-12 23:07–23:08) **disproved**
   that — zero `connChannelLost`/`retrying` events; the app never entered the
   retry path. The ring ended too early (at test 2's `msgFailed`, before the
   late arrival at 23:09:02), which initially obscured the flush-on-reconnect
   mechanism. Retitled/re-scoped the story to the half-open-socket bug.
3. **Second ring capture** (`e4f-11f1`, 2026-07-13 00:05–00:11) **proved** the
   flush-on-reconnect mechanism: two messages, one flush, minutes late.
4. **Pre-implementation verification** caught a second wrong premise: the
   initial root-cause write-up claimed relay control frames (`peer_online`)
   reset `_missedPings` via `onAppFrameObserved`. Verifying the code showed
   that's false — control frames route through `_onControl`, not
   `serverMessages`, and do NOT reset the counter. The 75s
   `ping_missed_room_offline` was the designed, correct behavior of the
   protocol-ping path. The real mechanism is the decoupling gap (above), not a
   reset bug. Both the corrected root cause and the superseded write-up are
   retained in the story for provenance.

**Lesson reinforced:** verify the reset/liveness path against the actual code
before implementing; a static trace that "explains" the symptom can still be
wrong about the mechanism. The ring captures were dispositive where the
static trace misled.

## Deploy question

**Yes — the fix needs an app APK rebuild + sideload to reach the phone.**
The fix is in `app/` (Flutter mobile), and `app/pubspec.yaml` is at `0.1.0+1`
(unchanged — the version was NOT bumped). The phone runs whatever APK was
last sideloaded; source edits are not live until a new APK is built and
installed. No relay, extension, or cockpit redeploy is needed (the fix is
app-only; the paired wire changes in `AGENTS.md` don't touch this path).

Build + sideload path (per `AGENTS.md`):
1. On the dev VM: cap Gradle heap (`-Xmx3G`) + redirect tmp off tmpfs, then
   `flutter build apk --release` (single fat APK; prefer over
   `--split-per-abi` given the VM's 11G RAM).
2. Copy the APK to the workstation with the phone attached, then `adb install -r`
   (the applicationId is already `dev.kevoun.outpostpi`, so `-r` keeps data).
3. Bump `app/pubspec.yaml` version before building if you want this tracked
   as a release (`release-deploy app-v1.x.y`).

Nothing on the VM runtime (relay container, pi-extension `dist/`) needs a
restart or rebuild for this fix — only the phone's APK.
