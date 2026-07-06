---
id: story-extension-suspend-fanout-on-peer-offline
kind: story
stage: drafting
tags: [pi-extension, relay, observability, bug, lifecycle]
parent: feature-reconnect-reproduction
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-05
updated: 2026-07-05
---

# Extension: suspend outbound fan-out for a gone app peer (consume `peer_offline`)

## Brief (the confirmed gap)

`idea-extension-pumps-into-dead-app-peer` reported that during a mobile
network drop, the pi-extension kept streaming transcript frames at the
now-gone app peer for ~2 minutes (until the turn ended), while the relay
logged a WARN per dropped frame:

```
WARN relay::handlers::connection_actor: dest (peer, room) not found, dropping
   from=YqWjpYw= dest=/uV6O0I= room=main bytes=200   (× dozens/sec)
```

**Code investigation (2026-07-05) confirmed the gap:**

1. **The relay DOES emit `peer_offline`.** `relay/src/peers/registry_event_publisher.rs:89-103` publishes `{"type": "peer_offline", peer, since_ts}` to presence subscribers when a peer transitions `BecameOffline` (N→0 connections). The relay knows the app is gone and tells subscribers.

2. **The extension does NOT consume `peer_offline` (or `peer_online`).** A grep for `peer_offline`/`peer_online`/`PeerOffline`/`PeerOnline` across `pi-extension/src/` (excluding the generated protocol) returns **nothing**. The types exist in the generated protocol (`protocol.generated.ts:417-418, 482-483`) but have no handler on the extension side.

3. **The extension's fan-out doesn't check liveness.** `OwnerMultiplexer.broadcast()` (`owner_multiplexer.ts:408-413`) iterates `this.channels.values()` and calls `channel.send(message)` per channel with a best-effort `try/catch` — it does NOT skip peers the relay has marked offline. So a dead app peer's channel keeps receiving `send()` calls (which hit the relay and get dropped with WARN) until the turn ends.

So the signal exists end-to-end (relay emits `peer_offline` → extension's relay transport receives it as a control frame) but the extension discards it. This is a real, code-actionable gap — no live reproduction needed to confirm it.

## Scope

- Consume `peer_offline` (and `peer_online`) control frames in the extension's relay transport / presence handling path — the frames already arrive; wire a handler.
- Track per-peer app presence state (online/offline) in the extension, derived from the relay's presence broadcasts.
- Suspend outbound fan-out (`OwnerMultiplexer.broadcast` / `sendToPeer`) for a peer the relay has marked offline, instead of pumping into the void. Resume when `peer_online` arrives (the app reconnected).
- Decide the suspension semantics:
  - **Drop** (discard frames while the peer is gone; the app rehydrates via `session_sync` on reconnect — the transcript event log is the source of truth, so no data loss, same as today but without the wasted pump + WARN flood).
  - **Queue** (buffer and flush on `peer_online`; risks unbounded growth + stale-order replay — likely wrong for a streaming turn).
  - **Drop-with-signal** (drop + emit a one-shot diagnostic so the operator/extension knows fan-out was suspended — fits the observability feature).
  The design should pick drop-with-signal (matches the relay's existing "drop + WARN" but moves it to the source so the relay stops seeing the flood), with a revisit condition if queueing becomes needed.
- Interact correctly with the existing `lateAttach` mechanism (a peer that reconnects while frames are in-flight) and multi-device Owners (multiple app peers for one Owner — `peer_offline` is per-peer, not per-Owner; only suspend when ALL of an Owner's app peers are gone).

## Why this is a story, not an inline fix

The fan-out suspension has real design decisions: drop-vs-queue semantics, the per-peer-vs-per-Owner distinction (multi-device), interaction with `lateAttach` and reconnect hydration, and where the presence state lives (the `OwnerMultiplexer`? a new presence projection?). The app's reconnect via `session_sync` already rehydrates the transcript from the server-side event log, so "drop while gone" is safe — but confirming that (and that no user-visible message is lost) is part of the design. This needs a design pass before implementation.

## Acceptance Criteria

- [ ] The extension consumes `peer_offline` and `peer_online` control frames (currently discarded — confirmed by grep).
- [ ] Per-peer app presence state is tracked in the extension.
- [ ] `OwnerMultiplexer.broadcast` (or the fan-out path) skips peers the relay has marked offline, instead of pumping into the void.
- [ ] Multi-device: an Owner with multiple app peers only suspends fan-out when ALL app peers are offline (not on the first `peer_offline`).
- [ ] Fan-out resumes on `peer_online` (app reconnect) without losing the in-flight turn (the app rehydrates via `session_sync`).
- [ ] A diagnostic signal (log / audit event) fires when fan-out is suspended/resumed so it's observable (fits the cross-side observability feature).
- [ ] No unbounded queueing (drop-with-signal, not buffer).
- [ ] The session-replacement harness (`story-session-replacement-harness`) still passes (the harness loads the real extension; if the extension's fan-out changes, confirm the harness's delivery assertions still hold).
- [ ] `corepack pnpm typecheck` + `corepack pnpm test` clean.

## Out of scope

- The relay's `peer_offline` emission (already correct — confirmed).
- The app's reconnect/rehydration (already works via `session_sync`; this story just stops wasting work during the dead window).
- The ~5min recovery latency (`idea-mobile-drop-slow-recovery`) — separate item; this story reduces wasted work during the window but doesn't shorten the window itself.
- Queueing/buffering frames for gone peers (drop-with-signal is the chosen semantics; revisit if a use case needs queueing).

## References

- Parent: `feature-reconnect-reproduction.md` (item `idea-extension-pumps-into-dead-app-peer`).
- Backlog: `.work/backlog/idea-extension-pumps-into-dead-app-peer.md` (the live observation).
- Confirmed gap:
  - `relay/src/peers/registry_event_publisher.rs:89-103` — emits `peer_offline`.
  - `pi-extension/src/protocol/generated/protocol.generated.ts:417-418,482-483` — types exist, no consumer (grep-confirmed).
  - `pi-extension/src/extension/owner_multiplexer.ts:408-413` — `broadcast` doesn't check liveness.
- Sibling (done): `feature-cross-side-observability` (the observability this consumes for the suspend/resume signal).
- Sibling (done): `story-session-replacement-harness` (the harness that must keep passing).
- `.agents/skills/pi-extension-typescript/SKILL.md` — extension lifecycle, `OwnerMultiplexer`, relay transport, presence.
- `.agents/skills/mobile-remote-coding/SKILL.md` — the reconnect state machine this fits into.

## Open design questions (resolve at design time)

- Where does per-peer presence state live? `OwnerMultiplexer` (it owns the channels) vs a new presence projection (separation of concerns)?
- Is the drop-with-signal observable via the extension's `audit.jsonl` (retroactive) or a `debugPrint`/log? The observability feature's ring log is app-side; the extension side is already `audit.jsonl` — prefer that.
- Does suspending fan-out affect the turn-state machine (the extension might need to mark the turn as "blocked on peer" rather than "streaming")? Or is fire-and-forget-drop sufficient (the turn completes server-side regardless)?
