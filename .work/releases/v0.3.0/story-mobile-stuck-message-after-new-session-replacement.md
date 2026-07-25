---
id: story-mobile-stuck-message-after-new-session-replacement
kind: story
stage: done
tags: [app, pi-extension, relay, bug, transport, session, lifecycle]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: v0.3.0
gate_origin: null
created: 2026-07-21
updated: 2026-07-24
reproduced: 2026-07-21
root_cause_confirmed: 2026-07-21
---

# Mobile message stuck + duplicated after `/new` — echo misattribution + delayed real echo

## Brief

Operator initiated `/new` from the mobile app (session replacement), then sent a
message. Two user-visible symptoms appear on the mobile side:

1. **Stuck / false failure.** The message appears stuck or shows a red
   "timeout" shortly after send, even though the extension received it and the
   agent turn eventually completes.
2. **Duplicate after the turn.** A second copy of the user's message appears
   in the chat log *after* the agent's turn, rather than the single send
   confirmation appearing immediately.

## Root cause: CONFIRMED 2026-07-21 (diagnostic agent + code-verified)

The replacement session context's `sendUserMessage` returns the full-turn
`Promise`, and Outpost-Pi unconditionally awaits it. That single mismatch
produces **both** symptoms. The `sync_` echo is a *symptom* of the await
ordering, not the *cause* of the stall.

### The chain (all verified in code)

1. Mobile `/new` → `session_new` action → `ctx.newSession({ withSession })`
   (`pi-extension/src/actions/handlers.ts:225-233`) →
   `_bindReplacementSessionContext` (`pi-extension/src/index.ts:1668-1681`)
   → `bindReplacementContext` re-arms `_messageApi` to the **replacement**
   context (`sdk_session_projection.ts:326-330`). The delivery log confirms:
   factory binding first, then `withSession` overwrites it.

2. Next message → `wakeAgent` → `await api.sendUserMessage(...)`
   (`sdk_session_projection.ts:680-688`). On the **factory** binding this
   returns `void` (Promise discarded → `wake_outcome` fires in ~100ms). On
   the **replacement** binding it returns `Promise<void>` that resolves only
   when the **entire agent turn** completes → `wake_outcome` fires at turn
   settlement (5.5s / 71s).

3. **The `sync_` echo falls out of the same await ordering.** The `cli_`→
   message mapping is recorded in `_confirmUserDelivery` (`index.ts:2334-
   2368`), which runs **after** the awaited wake. But `message_end` fires
   **during** the turn, calls `appendLegacySdkMessageToTranscript`
   (`sdk_session_projection.ts:468-475`), tries to look up the `cli_`
   mapping via `consumeDeliveredUserEvent`, finds nothing yet, and falls back
   to `sync_${ts}`. That `sync_` `user_input` broadcast is the fast wrong-id
   echo. The real `cli_` `user_message` echo only goes out after the await
   resolves, in `_confirmUserDelivery`.

### Smoking-gun evidence

The `sync_` id's epoch-millis matches the extension's receive time to the
millisecond:
- Repro #2: ext receives `05:05:19.095` → `sync_1784610319096` =
  `05:05:19.096` (+1ms). The timestamp is the SDK `message.timestamp` at
  `message_end`.
- Repro #1: ext receives `04:48:18.979` → `sync_1784609298980` =
  `04:48:18.980` (+1ms).

In both repros, `working:false` appears immediately before the real `cli_`
echo — i.e. the turn just finished. The "wake stall" is the agent turn
running; the agent was never stuck.

### `wake_outcome` semantic reinterpreted

`wake_outcome` does **not** mean "the agent was woken." It means "the
`sendUserMessage` call settled." On a factory binding those coincide (fast).
On a replacement binding, "settled" = "the whole turn finished." So the
5.5s/71s isn't a stalled wake — it's a mis-gated confirmation. The agent was
working the whole time.

## The deterministic pattern (across three repros)

The `msgSend`/`msgEcho` history across the full `4c2` capture exposes a
pattern that a single repro cannot:

- **Every healthy turn** (8-of-8 in the capture) gets two echoes carrying the
  **correct `cli_…` id** (matching the sent id), arriving ~100ms after send.
- **Every post-`/new` turn** (3-of-3: `cli_019f818a`, `cli_019f8300`,
  `cli_019f8310`) gets a first echo carrying a **`sync_<digits>` id instead of
  the `cli_` id** — the wrong id, every time.

This is deterministic, not intermittent: the `sync_` echo is the signature of
a post-`/new` first message.

## Primary reproduction (most documented) — 2026-07-21 05:04–05:06 UTC

Room `DnDBxuh7KVyt`, new session tail `bf863ec2` (replaced `e7cace53`).
This repro went to a peer session in the same cwd, so the orchestrator context
was preserved.

Cross-side traces:
- Mobile ring log: `debug/4c2-11f1-ae25-659bdda1075d.bin`
- Extension delivery log: `~/.pi/remote/debug/delivery.log`
- Relay log: `outpost-pi-relay` container, `RUST_LOG=info,relay=debug`

Messages:
- Initial test msg (pre-`/new`): `cli_019f830f-7b2d-7942-b578-f41b6eedad1b` —
  **healthy**: `msgSend` → two `cli_` echoes at +0.15s, wake 0.11s.
- The `/new`: extension `session_lifecycle new` at `05:04:36.623`, converged to
  new session `bf863ec2` by `05:04:37.301` (~0.7s).
- Post-`/new` msg: `cli_019f8310-724d-7787-908d-79a292ce4680` — **symptomatic**.

### Cross-side timeline (post-`/new` msg `cli_019f8310`)

| Time (UTC) | Side | Event |
|---|---|---|
| 05:05:19.095 | ext | `msg_received` `cli_019f8310…` source=app room `DnDBxuh7KVyt` |
| 05:05:20.978 | mobile | `workingConv working:true` mark_room_working |
| 05:05:21.029 | mobile | `msgSend` `cli_019f8310…` blocked:false |
| 05:05:21.331 | mobile | `wsIn envelope` (first agent-turn envelope) |
| 05:05:21.340 | mobile | **`msgEcho` id=`sync_1784610319096`** ← wrong id (`sync_`) |
| 05:05:21.386 | mobile | `replayDedup` sessionId=`…bf863ec2` eventIdTail=`784610319096` **dropped:true** |
| 05:05:24.557 | ext | `wake_outcome` ok:true messageApiArmed:true (**5.5s wake**) |
| 05:05:24.557 | ext | `msg_delivered` to session `bf863ec2` |
| 05:05:26.4x | mobile | agent-turn `wsIn envelope` burst begins |
| 05:05:26.580 | mobile | **`msgEcho` id=`cli_019f8310…`** ← real echo, **+5.6s**, after turn envelopes started |

Relay: clean — no `bad_envelope`, no drops for room `DnDBxuh7KVyt`. The `/new`
itself converged cleanly (~0.7s extension, `room_ended`→`room_announced` on
mobile at `05:04:38.6`→`05:04:39.4`).

### What the timeline shows

- The `sync_` echo arrives fast (+0.3s) but carries the wrong id and is
  **dropped by `replayDedup`** — it is not the rendered duplicate.
- The real `cli_` echo arrives at +5.6s — after the agent-turn envelopes
  already began streaming at `05:05:26.4x`. So the send confirmation appears
  *after* the agent's turn — matching "second copy of the message after the
  agent's turn."
- The `cli_` echo delay (5.6s) equals the extension wake delay (5.5s) to
  within measurement noise. **The echo delay is downstream of the wake stall,
  not an independent app bug.**

## Earlier reproductions (same symptom class, less complete captures)

### Repro — 2026-07-21 04:47–04:50 UTC (room `83MK6OkhBrcQ`, msg `cli_019f8300`)

- Mobile log: `debug/4c0-11f1-ae25-659bdda1075d.bin`
- Same deterministic `sync_` echo (`sync_1784609298980`) dropped by
  `replayDedup`; real `cli_` echo arrived +71s.
- Wake latency **71s** (vs. ~100ms baseline) → app's 20s echo timeout fired
  → `msgFailed send_timeout "no echo in 20s"` at `04:48:40`.
- First agent-turn envelopes arrived at `04:48:32` (during the stall window).

### Repro — 2026-07-20 21:59 UTC (room `SF_DCbXsmreE`, msg `cli_019f818a`)

- Mobile log: `debug/486-11f1-ae25-659bdda1075d.bin`
- Same deterministic `sync_` echo (`sync_1784584771833`); real `cli_` echo
  arrived ~2h later.
- Wake latency ~2h — but this was because the operator set the session aside
  and the wake only fired on return. The mobile capture ended at `21:59:53`,
  so the late wake trigger was not captured on the mobile side.

## What IS confirmed (the load-bearing facts)

1. **The `sync_` echo is the `/new` signature.** Every post-`/new` first
   message gets a `sync_<digits>`-id echo instead of the sent `cli_` id;
   every healthy turn echoes the correct `cli_` id. Deterministic, 3-for-3
   post-`/new` vs. 8-for-8 healthy in the `4c2` capture.

2. **The `sync_` echo is dropped by `replayDedup`** (`dropped:true`), so it is
   *not* the rendered duplicate. Do not chase it as the duplicate source.

3. **The real `cli_` echo delay equals the extension wake delay** (5.6s↔5.5s,
   71s↔71s). They are one stall, not two bugs. The "stuck" symptom and the
   "duplicate after turn" symptom are facets of the same wake stall.

4. **The relay is clean** in every repro — no drops, no `bad_envelope`, no
   errors. The failure is on the app↔extension delivery path, not the relay.

5. **The `/new` itself converges cleanly** in <1s on both sides in every repro.
   The stall is on the *first message after* the replacement, not the
   replacement itself.

## Open questions (ANSWERED by the confirmed root cause)

1. **Where does the `sync_` echo originate?** ANSWERED: `sdk_session_projection.ts:468-475` — `appendLegacySdkMessageToTranscript` falls back to `sync_${ts}` when `consumeDeliveredUserEvent` finds no mapping. The mapping isn't recorded yet because `_confirmUserDelivery` (which records it) runs after the awaited wake.

2. **Why is the real `cli_` echo delayed?** ANSWERED: `_confirmUserDelivery` (`index.ts:2334-2368`) — which records the `cli_` mapping and broadcasts the real `user_message {id: cli_…}` echo — runs after `await api.sendUserMessage(...)`. On the replacement context, that await gates on the full agent turn. On the factory context, it returns `void` immediately.

3. **Is the `sync_` echo the cause or a symptom?** ANSWERED: symptom. Both symptoms share one cause: the replacement context's `sendUserMessage` exposes the full-turn Promise, and Outpost-Pi awaits it. The `sync_` echo is fast because `message_end` fires during the turn (before the mapping exists); the `cli_` echo is slow because it's gated on the awaited turn completing.

## The red "timeout" on pressing "New session"

The operator observed a brief red "timeout" when pressing "New session" in
repro #2. There is **no `msgFailed` event for the `/new` command** in the
mobile log (only 2 `msgFailed`s, both for `cli_` user messages). So the red
timeout on `/new` is either a UI affordance that does not log through the
`msgSend`/`msgEcho`/`msgFailed` channel, or it is the `sync_` echo mechanism
hitting the `/new` command frame. The `/new` replacement itself was fast
(`room_ended`→`room_announced` in ~0.8s), so it is not an actual replacement
failure.

## Disposition

Reproduced against post-0.2.0 code. Root cause CONFIRMED and code-verified
(2026-07-21). The two user-visible symptoms (stuck + duplicate) are facets
of one mechanism: the replacement context's `sendUserMessage` returns the
full-turn `Promise`, and Outpost-Pi unconditionally awaits it.

The fix has a genuine design decision (record-mapping-order fix vs.
await-semantics contract change for `wake_outcome`), so it is routed to a
feature for design: `feature-replacement-session-wake-confirmation`.

Unbound from any release (not blocking 0.2.0, which has shipped). Route
through `feature-reconnect-reproduction`.

## Related (different symptom class — do not conflate)

`story-mobile-double-messages-on-session-history-replay.md` describes a
*different* duplication mechanism (`session_history` replays with mismatched
eventIds). That mechanism does **not** appear in these repros — neither
clean capture contains any `session_history` frames. Do not route diagnostic
agents to that story for this repro; the duplication here is the
delayed-real-echo mechanism documented above.

## References

- Primary capture: `debug/4c2-11f1-ae25-659bdda1075d.bin` (2026-07-21, full
  echo history across healthy + post-`/new` turns — the most documented repro).
- Earlier captures: `debug/4c0-11f1-ae25-659bdda1075d.bin` (04:47–04:50),
  `debug/486-11f1-ae25-659bdda1075d.bin` (2026-07-20 21:59).
- Extension delivery log: `~/.pi/remote/debug/delivery.log`
  (`OUTPOST_PI_DEBUG_LOG=1`).
- `pi-extension/src/session/sdk_session_projection.ts` — echo / wake paths
  (candidate for the `sync_` echo origin; unconfirmed).
- Parent: `feature-reconnect-reproduction.md`.

## Reconciliation (2026-07-23) — closed as landed

The fix this story was routed for shipped in
`feature-replacement-session-wake-confirmation` (**done** 2026-07-21):
Problem A fixed (the `cli_`→message mapping is reserved BEFORE the awaited
wake, so `message_end` broadcasts the real `cli_` id immediately — no `sync_`
fallback), Problem B deliberately deferred per option B1. Reviewed (standard,
approved) and **live-verified on the operator's phone 2026-07-22** (capture
`debug/591-11f1-9656-5799420aa9fe.bin`): post-`/new` echo carried the correct
`cli_` id at +71ms, zero `sync_` echoes, no false `send_timeout`, no stuck
message, no duplicate after the turn.

Both user-visible symptoms in this story's brief are facets of that one
mechanism and are resolved. Closing `drafting → done` as retroactive capture
of work landed and verified under the routed feature; no review lane
(child-story checkpoint of an already-reviewed feature).

Residual, DIFFERENT symptom class (not this story): the brief red "timeout"
on pressing "New session" itself — no `msgFailed` logged, replacement
converges in ~1s. Tracked separately in
`.work/backlog/idea-mobile-new-session-red-timeout-affordance.md`.
