---
id: story-extension-delivery-path-ring-log
kind: story
stage: drafting
tags: [pi-extension, observability, bug]
parent: feature-cross-side-observability
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-08
updated: 2026-07-08
---

# Extension delivery-path ring log (the missing third leg of cross-side observability)

## Brief

The phone has a persistent ring log (`debug/*.bin`, Units 1–4 of the parent
feature). The relay now has a persistent file sink + `env_id_tail` correlation
(`story-relay-retroactive-file-logging`, deployed 2026-07-08). The
**extension** — the workstation side where `messageApi` goes null, where
`bindApi` re-arms, where `wakeAgent` decides delivered-vs-recoverable, and
where `session_start`/`session_shutdown` fire — has **no persistent log of the
delivery path.** The existing `audit.jsonl` (`session/broker.ts`) records
cross-PC mesh routing (`received`/`delivered`/`ackStatus`), NOT the
phone→Pi message-delivery / session-replacement path. The parent feature's
claim that "the extension side is already retroactively diagnosable
(`audit.jsonl`)" is misleading for this purpose: it is retroactive for *mesh
routing*, not for the delivery path the stuck-state bug lives on.

This is the gap that made this session's wrong premise possible: the
stale-ctx vs transport-room-mismatch disambiguation could only be reasoned
about from phone-side logs that cannot see the workstation's `messageApi`
state or the `/reload` recovery. With three correlated logs (phone `msg.id`
↔ relay `env_id_tail` ↔ extension `app user_message id` + `messageApi`
binding state), the chronology becomes a grep instead of an inference.

## Why this is the highest-leverage remaining gap

The parent feature's brief opens: *"the boundary bug class exists because we
are observability-blind on the phone (and relay) side where the bugs
manifest."* That framing missed that the **extension** is equally blind on
the delivery path — and it is the side where the root cause of the
stuck-state bug actually lives (`messageApi` null after `/new`/`/resume`/
`/fork`). Every wrong fix this session (the reverted `factoryApi` re-arm, the
null-window-race framing, the transport-vs-stale-ctx confusion) was
uncheckable from logs because the extension half had none. This story closes
that.

## Scope (the capture surface)

A bounded in-memory ring buffer flushed to a file, gated behind an env var
(`REMOTE_PI_DEBUG_LOG`), capturing the delivery-path state transitions keyed
by the same message `id` the phone and relay use. Privacy: routing metadata +
message `id` tail + outcome reasons only — never message text, images, tool
args, or `ct` (matches the relay's posture and the app ring log's scrub).

### Capture points (grounded in current source)

All in `pi-extension/src/index.ts` + `pi-extension/src/session/sdk_session_projection.ts`.
The message `id` is `msg.id` (the phone's `cli_...` id) — already the join key
used in `console.warn` lines (`app user_message id=${msg.id}`).

| Event | Site | Fields | Why |
|---|---|---|---|
| `msg_received` | `_deliverUserMessage` (~L2125) | `id`, `source` (app/queued), `steer` | inbound arrival — the phone's `msg-send` counterpart on the extension side |
| `wake_outcome` | `wakeAgent` (`sdk_session_projection.ts:571`) | `id`, `ok`, `recoverable`, `detail` (tail), `messageApi_armed` (bool) | **the core diagnostic** — distinguishes delivered / null-window / stale-throw; `messageApi_armed` proves the stuck-null |
| `msg_delivered` | `_confirmUserDelivery` (~L2230) | `id`, `session_id` (tail) | success echo sent — correlates to phone `msg-echo` |
| `delivery_pending` | `_enqueuePendingDelivery` (~L2248) | `id`, `queue_len`, `ttl_ms` | message queued during null window — correlates to phone `delivery_pending` |
| `queue_drained` | `_drainPendingDeliveryQueue` (~L2292) | `id`, `wake_ok` | replay attempt after re-arm |
| `queue_dropped` | overflow/TTL/fail paths (~L2251,2279,2287) | `id`, `reason` | permanent failure — correlates to phone `msg-failed` |
| `message_api_armed` | `bindApi` (projection L133, index L794/820) | `via` (factory/withSession), `session_id` (tail) | **re-arm event** — proves `/reload`/`session_new` recovered |
| `message_api_null` | `forget`/`clearStaleContexts` (L768,297) | `reason` (stale/shutdown/replacement) | **the null-window open** — the stuck-state signature |
| `session_lifecycle` | `session_start`/`session_shutdown` hooks (composition_root.ts:55, index L1607) | `reason` (startup/reload/new/resume/fork/quit), `session_id` (tail) | the precursor that triggers the null window — the missing "what happened before the phone failed" |
| `command_ctx` | `bindCommandContext`/`clearStaleContexts` (L137,297) | `armed` (bool), `via` (slash/withSession) | the `/reload`-button feasibility question — is `commandCtx` null in the stuck state? |

### What is NOT captured (privacy)

- Message text, images, tool args/results, `ct`, signatures, full pubkeys.
- The `detail` field on `wake_outcome`/`queue_dropped` is tail-truncated
  (e.g. the stale-throw message) — enough to classify, not the full stack.
- `session_id` is tail-only (matches relay's `peer_tail` convention).

## Design

### Adapter shape (mirrors the app ring log + relay file sink)

- **Bounded in-memory ring** (cap ~512 KiB encoded; drop oldest on append —
  same truncation-on-append discipline as the app `DebugLogImpl`).
- **File-backed** at `$REMOTE_PI_HOME/debug/delivery.log` (or
  `~/.pi/remote/debug/delivery.log`), appended + flushed on critical events
  (the app's `_immediateFlushTags` discipline: `wake_outcome`,
  `queue_dropped`, `message_api_null`, `session_lifecycle` flush
  immediately; routine events debounce 2s).
- **Gated behind `REMOTE_PI_DEBUG_LOG=1`** (default off — matches the app's
  debug-toggle posture; the extension runs in the operator's TUI/daemon, so
  an env var is the right gate, not a UI toggle). When off, `log()` is an
  early no-op.
- **Never throws**: `log()` catches `Object`; failures emit a `console.warn`
  and never rethrow (the logger must not break delivery).
- **Crash-resilient**: critical events flush immediately so the diagnostic
  tail survives a crash (the whole point — the stuck-state failure is the
  thing we need to see after the fact).

### Typed events (single source of truth)

A `DeliveryDebugEvent` sealed class + `DeliveryDebugTag` enum in a new
`pi-extension/src/session/delivery_debug_log.ts`, mirroring the app's typed
`DebugEvent` registry. Each variant owns its allowed fields + scrub. The tag
is an enum, not a free string — the registry IS the capture surface (same
discipline as the app ring log, review B2/C1).

### Wiring

- A `DeliveryDebugLog` port on `SdkSessionProjectionOptions.outputs` (the
  projection already has an `outputs` bag for `onStaleMessageApi`,
  `publishRoomMeta`, etc. — this fits the same shape).
- The projection emits `message_api_armed`/`message_api_null`/`wake_outcome`/
  `command_ctx` from its own state transitions (it owns `messageApi`/
  `commandCtx`/`eventCtx`).
- `index.ts` emits `msg_received`/`msg_delivered`/`delivery_pending`/
  `queue_drained`/`queue_dropped`/`session_lifecycle` from its delivery +
  hook code.
- The factory wires a single `DeliveryDebugLogImpl` (file-backed) when
  `REMOTE_PI_DEBUG_LOG=1`, else a no-op.

## Acceptance Criteria

- [ ] `REMOTE_PI_DEBUG_LOG=1` enables a bounded ring + file at
      `~/.pi/remote/debug/delivery.log`; default off is a no-op.
- [ ] A `user_message` arrival emits `msg_received { id }`; a successful
      delivery emits `msg_delivered { id }` — the `id` matches the phone's
      `msg-send id` and the relay's `env_id_tail`.
- [ ] A null-`messageApi` `wakeAgent` emits `wake_outcome { id, ok:false,
      recoverable:true, messageApi_armed:false }` — the stuck-null signature.
- [ ] `bindApi` (factory `/reload` or `withSession` re-arm) emits
      `message_api_armed { via }`; `forget`/`clearStaleContexts` emits
      `message_api_null { reason }`.
- [ ] `session_start`/`session_shutdown` emit `session_lifecycle { reason }`
      — the precursor that opens the null window.
- [ ] `command_ctx { armed, via }` records whether `commandCtx` is null in
      the stuck state (answers the `/reload`-button feasibility question
      from evidence, not static trace).
- [ ] No message text / images / tool args / `ct` / full pubkeys in any
      event; `detail`/`session_id` are tail-truncated.
- [ ] `log()` never throws; critical events flush immediately; routine
      debounce 2s.
- [ ] `corepack pnpm typecheck` + `corepack pnpm test` clean; a regression
      test asserts the expected events fire on a deliver / null-window /
      re-arm path (fake `DeliveryDebugLog`).

## Pre-mortem risks

- **Volume in a flap storm.** Mitigated by the 512 KiB cap + drop-oldest;
  `session_lifecycle` + `message_api_null` are low-frequency (one per
  replacement), `wake_outcome` is one per message. The cap covers the
  operator's "few hours" window.
- **Masking the real failure.** The TTL + `queue_dropped` fallback ensures a
  genuine failure still surfaces (mirrors the shipped tolerance layer).
- **Stale module after `/reload`.** Per AGENTS.md, a `dist/` change needs a
  full pi restart to load — so enabling this log requires a restart, not
  just `/reload`. Document in the deploy note.
- **Privacy drift.** The typed registry makes the scrub explicit per-event;
  a registry test asserts no forbidden keys (`text`, `images`, `args`,
  `result`, `ct`, `prompt`, `body`), mirroring the app ring log's test.

## Out of scope

- The session-replacement integration harness (Unit 7 of the parent feature
  — separate, highest-risk, needs an SDK feasibility spike).
- Transport-frame observability (Unit 6 — parked follow-on).
- Changing the app or relay log formats (both already ship the `id`
  correlation key this log joins to).

## Relationship to the stuck-state bug

This log is what makes `story-fix-stale-ctx-messageapi-rearm-on-reload`
diagnosable from evidence: the `message_api_null { reason }` +
`session_lifecycle { reason }` lines show the precursor and the null-window
open; `wake_outcome { messageApi_armed:false }` proves the stuck-null; and
`message_api_armed { via:"factory" }` after a `/reload` proves the recovery.
It does NOT fix the bug — it makes the bug (and the `/reload`-button
feasibility) answerable from logs instead of static traces and inference.

## References

- Parent: `feature-cross-side-observability` (Units 1–4 app-side done; this
  is the extension half that was never decomposed).
- Deployed relay half: `story-relay-retroactive-file-logging` (done 2026-07-08).
- The bug this unblocks diagnosis of: `story-fix-stale-ctx-messageapi-rearm-on-reload`.
- App ring log shape (the design this mirrors): `feature-cross-side-observability`
  Units 1–2 (`DebugEvent` registry + `DebugLogImpl`).
- `pi-extension/src/session/sdk_session_projection.ts` — `messageApi`/
  `commandCtx`/`eventCtx` lifecycle + `wakeAgent` (L571).
- `pi-extension/src/index.ts` — `_deliverUserMessage` (L2125),
  `_confirmUserDelivery` (L2230), `_enqueuePendingDeliveryQueue` (L2248),
  `_drainPendingDeliveryQueue` (L2292), `session_start`/`session_shutdown`
  hooks (composition_root.ts:55).
- `pi-extension/src/session/broker.ts:549` — the existing `audit.jsonl`
  (mesh routing only; NOT the delivery path — the misconception this
  story corrects).
