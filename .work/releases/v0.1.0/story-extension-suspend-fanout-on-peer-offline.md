---
id: story-extension-suspend-fanout-on-peer-offline
kind: story
stage: done
review_addressed: 2026-07-05
tags: [pi-extension, relay, observability, bug, lifecycle]
parent: feature-reconnect-reproduction
depends_on:
  - feature-cross-side-observability
release_binding: v0.1.0
gate_origin: null
created: 2026-07-05
updated: 2026-07-07
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

## Implementation notes

### Locked design decisions

- **Presence state owner:** `OwnerMultiplexer` owns per-peer app channel lifetime (`channels`) and now owns the relay-derived `offlinePeerIds` set. A separate presence projection would add another source of truth for the same peer ids; keeping it with the channel registry lets `broadcast`, `detach`, `detachAll`, and `lateAttach` converge in one lifecycle owner.
- **Per-peer vs per-Owner:** the extension channel model is `Map<peerId, PeerChannelHandle>`, not `Map<owner, Set<channel>>`. A multi-device Owner therefore appears as multiple app peer ids/channels. Relay `peer_offline` is also peer-id scoped and fires on N→0 connections for that peer id, so fan-out suspension is per peer id: an offline phone is skipped while other app peer channels keep receiving frames.
- **Drop-with-signal:** no queue/buffer is introduced. `OwnerMultiplexer.broadcast` skips offline peer ids and drops those live stream frames; reconnecting apps recover via `session_sync`. The diagnostic uses the extension-side Pi custom message/notification path (`remote-pi:fanout-presence`) because no app-owner `audit.jsonl` writer/debugPrint facility exists; it logs only the peer short id, state, and optional `sinceTs`, never transcript payloads. The signal is emitted once on suspend and once on resume, not per dropped frame.
- **Resume/lifecycle:** `peer_online` clears the peer's offline state. `attach`/reattach also clears stale offline state so a reconnect/late attach during an active turn cannot stay stuck suspended. `detach`, `detachAll`, and `detachAllForRelayDrop` clear offline flags to avoid stale state across relay/session lifecycle boundaries.

### Files changed

- `pi-extension/src/extension/relay_transport.ts`
  - Added generated-type-backed decoding for relay presence control frames (`peer_offline`, `peer_online`, and `presence`).
  - Added `onControlFrame` to the relay transport adapter and dispatches control frames from the single relay message listener, preserving existing outer-envelope listener behavior.
- `pi-extension/src/extension/owner_multiplexer.ts`
  - Added `offlinePeerIds`, `markPeerOffline`, `markPeerOnline`, and `isPeerOffline`.
  - Changed `broadcast` to skip offline peer ids.
  - Added one-shot suspend/resume diagnostic callback support.
  - Clears offline state on detach/detachAll/relay-drop and on reattach.
- `pi-extension/src/index.ts`
  - Wires relay control frames to `_owners.markPeerOffline` / `_owners.markPeerOnline`.
  - Subscribes the relay presence stream for attached owner peer ids with `subscribe_presence`.
  - Emits privacy-preserving `remote-pi:fanout-presence` diagnostics plus UI notify on suspend/resume.
- `pi-extension/src/extension/owner_multiplexer.test.ts`
  - Added tests for offline skip/resume, one-shot diagnostics, and late-attach/reattach clearing stale offline state.
- `pi-extension/src/extension/relay_transport.test.ts`
  - Added tests for decoding and dispatching `peer_offline`/`peer_online` from the relay message stream.

### Verification

Targeted tests including the required session-replacement harness:

```text
$ PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache corepack pnpm exec vitest run src/extension/owner_multiplexer.test.ts src/extension/relay_transport.test.ts test/sdk-session-replacement.test.ts
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were ignored: "pnpm.onlyBuiltDependencies". See https://pnpm.io/settings for the new home of each setting.

 RUN  v4.1.9 /home/agent/projects/remote_pi/pi-extension


 Test Files  3 passed (3)
      Tests  15 passed (15)
   Start at  19:35:12
   Duration  1.46s (transform 454ms, setup 0ms, import 930ms, tests 581ms, environment 0ms)
```

Typecheck:

```text
$ PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache corepack pnpm typecheck
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were ignored: "pnpm.onlyBuiltDependencies". See https://pnpm.io/settings for the new home of each setting.
$ tsc --noEmit
```

Full test suite:

```text
$ PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache corepack pnpm test
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were ignored: "pnpm.onlyBuiltDependencies". See https://pnpm.io/settings for the new home of each setting.
$ vitest run

 RUN  v4.1.9 /home/agent/projects/remote_pi/pi-extension


 Test Files  47 passed (47)
      Tests  749 passed | 3 skipped (752)
   Start at  19:35:18
   Duration  7.59s (transform 3.16s, setup 0ms, import 7.20s, tests 16.00s, environment 5ms)
```

## Review fixes (adversarial review, 1 pass)

NEEDS FIXES → APPROVED after 1 fix pass (openai-codex/gpt-5.5):

- **[I1] fail-fast violation in `presence` decoding** (`relay_transport.ts`):
  the original `flatMap(... return [])` silently dropped malformed
  `presence.states` entries, returning a partial frame instead of rejecting
  it — could mask a relay bug or a missed offline/online transition. Fixed
  with a `for...of` loop that `return null`s the WHOLE frame on the first
  malformed entry (missing non-empty `peer`, non-boolean `online`, or invalid
  `since_ts`). Regression test: "rejects malformed presence frames (fail-fast
  at the boundary)" asserts null for non-array states, empty peer, non-boolean
  online, non-number since_ts — and FAILS under the old flatMap logic (which
  returned a partial frame).

- **Nit (dispatch-path test)**: added "dispatchRelayMessage still forwards raw
  control-frame lines to outerMessageHandlers" to prove the subtle preservation
  of the legacy envelope path (a control frame lacks `ct`, so
  decodeOuterEnvelope returns null and it's ignored; the line is still
  forwarded so the path is unchanged).

- **Nit (presence tests)**: added "decodes presence frames and tolerates
  null/absent since_ts" for valid presence with mixed since_ts shapes.

Final verification: `corepack pnpm test` → 752 passed | 3 skipped (was 749;
+3 new tests). `corepack pnpm typecheck` clean. The session-replacement
harness still passes.

## Post-deploy fix: stop injecting fan-out telemetry into the agent context (2026-07-08)

**Regression found in production.** The `onFanoutPresenceChanged`
callback called `_sendPiMessage({ customType: "remote-pi:fanout-presence",
content, display: false })`, which routes through the SDK's
`sendCustomMessage` → `appendCustomMessageEntry` and adds the fan-out text
to the agent's conversation as a `custom` message. `display: false` only
suppresses the TUI bubble render — it does NOT keep the message out of
the agent's context. So the agent saw "[remote-pi] Fan-out suspended for
app peer=..." as part of its conversation and responded to it ("Re: the
repeated my/xN94M fan-out suspensions..."), disrupting work. The
`_notify` call also spammed the TUI footer with a Warning per flap.

A flapping mobile connection (the phone backgrounding/suspending the
WebSocket every 1-3 min, normal mobile behavior) made this constant —
every suspend/resume cycle injected two messages into the agent context.

**Fix:** removed the `_sendPiMessage` and `_notify` calls entirely.
Fan-out suspend/resume is relay-transport telemetry, not agent-facing
content — it now emits a `console.warn` only (the log/audit channel the
story's design originally specified, not `sendMessage`). The
`owner_multiplexer` still emits `onFanoutPresenceChanged` (the callback
contract is unchanged); only the `index.ts` handler's side effect changed.

**Follow-up fix (same day):** `console.warn` was ALSO unsuitable — pi
surfaces extension `console.warn` to the TUI as a notification
(`runner.js:297`), so the spam persisted after the first fix. Made the
handler fully silent (`void` the args, no output at all). Fan-out
suspend/resume fires on every mobile connection flap (normal mobile
behavior), so any TUI output is too noisy. If diagnostics are ever needed
they should go to a debug log file, not the TUI.

**Verification:** `corepack pnpm typecheck` clean; `corepack pnpm test` →
765 passed | 3 skipped (was 752; the delta is unrelated test growth). The
`owner_multiplexer.test.ts` one-shot diagnostic tests still pass (they
assert the callback is invoked, not what `index.ts` does with it).
