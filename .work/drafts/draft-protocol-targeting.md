# DRAFT — PROTOCOL.md addition: App↔Pi message targeting & delivery

> **Status: DRAFT, 2026-07-04. Premise corrected by operator (Q2).**
>
> The operator clarified the actual scenario: they started a **second pi**
> (`remote_pi#2`) to test this session's fixes (a fresh pi loads the rebuilt
> `dist/`). The stale `internal_error` occurred **in that `#2` session itself**
> — the phone was talking to `#2`, on `#2`'s room, and `#2`'s own `wakeAgent`
> threw stale. There was **no cross-room leak** and **no same-room collision**
> (the cwd-lock disambiguated to distinct rooms, as designed).
>
> So the real bug shape is: **a freshly-started pi, on its own room, throwing
> stale on an inbound phone message to its own session.** That is the
> **same-session stale wake** case that the shipped tolerance fix
> (`feature-session-stable-message-delivery-stale-wake-tolerance`, done)
> is supposed to cover. The open question is whether (a) the fix wasn't
> actually live in `#2` (dist not rebuilt / `#2` not restarted after the
> rebuild), or (b) the fix is live but there's a path it doesn't cover.
>
> **This is directly testable and should NOT be inferred further.** The
> investigation is: reproduce in a single fresh pi, confirm the fix is loaded
> (`grep -c factoryApi`/`recoverable` in `dist/`), and observe whether the
> stale error still fires. Do not spec the contract until that's answered —
> the contract draft below is retained as background but its "collision
> conditions" section is INVALIDATED and should be deleted once the real
> shape is confirmed.
>
> Not committed to `PROTOCOL.md`. Grounded in the actual relay + extension
> source (`relay/src/peers/connections.rs:send_to_room`, `registry.rs:30-45`,
> `pi-extension/src/rooms.ts`, `pairing/storage.ts`).

## The targeting model (as-implemented, to be pinned as contract)

### Identity & room derivation

- **`owner_pk`** — the Pi's Ed25519 long-term identity, **per-machine**
  (`pairing/storage.ts`: keyring service `dev.remotepi.pi` / account
  `longterm-ed25519`, file fallback `~/.pi/remote/identity.json`). Every Pi
  process on one host shares the same `owner_pk`. The App pairs against this
  key; it does not identify an individual Pi process.
- **`room_id`** — derived from `(cwd, assigned-agent-name)` via `roomIdFor`
  (`pi-extension/src/rooms.ts`). Same `(cwd, name)` → same `room_id`.
  `realpath(cwd)` is hashed so symlinked cwds collapse to one room.
- **Name disambiguation via the cwd-lock** — the assigned agent name is
  resolved by a **cross-process** UDS lock
  (`pi-extension/src/session/cwd_lock.ts`, `<root>/.pi/remote/locks/<roomId>.sock`).
  The first Pi to claim a cwd gets the default name (`folder`); a second Pi
  in the same cwd gets `folder#2` → a **distinct `room_id`**. So under
  normal operation, two Pi processes in the same cwd do **NOT** share a room.

### Relay data-plane forwarding (the load-bearing contract)

The relay routes data-plane messages by **explicit `(owner_pk, room_id)`**
target. Forwarding is **fanout to every live connection** at that
`(owner_pk, room_id)`, skipping the originator's connection
(`relay/src/peers/connections.rs:send_to_room`, `registry.rs:30-45`):

> Every live conn in the corresponding `Vec` receives a copy. The
> originating connection skips itself via `from_conn_id`, so a multi-device
> app sees outgoing messages only on the device that sent them.

This is **by design for multi-device owners**: N devices (phone, tablet,
laptop) share one `owner_pk` and may each hold a connection at the same
`room_id`; all of them receive every message so they stay in sync.

### What this means for Pi↔Pi on one host (the undefined case)

Two Pi processes on one host with the **same assigned name** (i.e. the
cwd-lock did NOT disambiguate — see "Collision conditions" below) share both
`owner_pk` and `room_id`. The relay treats them as **two connections of the
same multi-device owner** and **fans out every message to both**.

So when the App sends a `user_message` to `(owner_pk, room)`:
- **Both** Pi processes receive it.
- Each Pi's extension runs its own `_routeClientMessageFrom` →
  `validateClientSession` (the session gate) → possibly `_deliverUserMessage`.
- The App's `user_message` carries a `session_id` targeting **one** specific
  Pi session. The other Pi's `currentRemoteSessionId` will (normally) differ
  → that Pi's session gate rejects with `session_mismatch` before delivery.

### Collision conditions (when the cwd-lock fails to disambiguate)

The cwd-lock is the **only** mechanism preventing two same-named Pis from
sharing a room. It fails to disambiguate when:

1. **One Pi bypasses the lock.** A code path that starts the relay without
   acquiring the cwd-lock (`_cmdStart` without `_cmdJoin`) would derive the
   default-name room while another Pi holds it. *Needs verification: does
   every start path acquire the lock? The daemon auto-init and control-channel
   paths are the likely suspects.*
2. **Different lock namespaces.** POSIX UDS vs Windows named pipe vs a
   containerized daemon with a different `<root>` would not see each other's
   lock.
3. **Stale lock + race.** A crashed Pi's leftover `.sock` is self-healing
   (`tryConnect` → unlink → retry), but a tight race between two startups
   could both bind-detect before either claims.

This is the **open question** for the operator's reported scenario: which
collision condition produced "two Pis, same CWD, same room"? Pinning the
contract makes this a **detectable violation** rather than an undefined
behavior.

## The contract to pin

1. **`owner_pk` is per-machine, not per-Pi-process.** Document this
   explicitly. The App pairs with a machine, not a process.
2. **`room_id` is per-`(cwd, assigned-name)`.** The cwd-lock is the
   disambiguator; two same-named Pis in one cwd is a **lock violation**,
   not a supported topology.
3. **Relay forwarding is fanout to every conn at `(owner_pk, room)`.** This
   is intentional for multi-device owners and is the contract the App
   relies on for cross-device sync.
4. **A `user_message` targets exactly one Pi session via `session_id`.**
   When fanout delivers it to a Pi whose `currentRemoteSessionId` differs,
   that Pi's session gate rejects with `session_mismatch` and **must not**
   deliver to its agent.
5. **The `session_mismatch` rejection is a re-sync signal, not an error to
   display.** (← this is the decision `story-foreign-session-user-message-tolerance`
   needs; it's the contract call, flagged here as the open decision.)

## What pinning this unblocks

- `story-foreign-session-user-message-tolerance` — becomes "implement
  contract #5: the App treats `session_mismatch` on a `user_message` as a
  re-sync trigger, not a displayed error." A one-place app-side change
  grounded in the contract, not a guess.
- The reopened `story-fix-stale-ctx-messageapi-rearm-on-reload` — the
  stale-ctx lifecycle is a separate contract (the session-lifecycle section,
  next to draft) but it depends on #4 (a `user_message` targets one session).
- The multi-instance collision — becomes a **detectable lock violation**
  (extension can refuse to start, or warn, when it detects a same-name
  sibling already holding the room) instead of undefined behavior.

## Open decisions for the operator (sanity-check these)

- **#5 wording (operator Q1 — refine, do NOT blunt-treat):** the operator
  pushed back on treating *all* `session_mismatch` as a silent re-sync. Better
  direction: **disambiguate the two cases with a typed field or distinct codes.**
  Instead of one `session_mismatch`, emit e.g. `session_superseded` (your
  session_id is stale because the pi replaced it → re-sync) vs
  `wrong_target`/`not_my_session` (this message was for a different pi → silent
  drop, no error). This needs wire-format design (new error codes in the
  generated protocol + app-side handling per code) and is a cleaner answer than
  the blunt instrument. The extension CAN distinguish these: it knows whether
  its `currentRemoteSessionId` is a *successor* of the phone's id (superseded)
  vs an *unrelated* id (wrong target) — though "successor" detection needs a
  session-history/parent-chain check. Scope as part of the contract work.
- **Collision policy:** **INVALIDATED by operator Q2** — there was no collision
>  (distinct rooms). The real question is the routing leak, not a collision
>  policy. Defer until the routing path is investigated.
- **Is this the right level of `PROTOCOL.md`?** This is the App↔Pi data-plane
  contract; `PROTOCOL.md` already documents the Pi↔Pi envelope `to_room`
  contract. They should be consistent and cross-reference. Confirm this
  belongs in `PROTOCOL.md` and not a separate `docs/ARCHITECTURE.md` section.

## What this draft deliberately does NOT cover

- **The stale-ctx lifecycle contract** (when a captured ctx may be used,
  what tolerates it when stale) — that's the *next* draft, the
  session-lifecycle section. It's a separate state machine and should be its
  own artifact. This draft is only the targeting model.
- **The reconnect state machine** — also a separate state machine (the
  mobile-remote-coding skill lists the states); separate draft.
- **Canonical transcript-event identity** (the duplication/reorder root
  cause) — separate, app-side.
