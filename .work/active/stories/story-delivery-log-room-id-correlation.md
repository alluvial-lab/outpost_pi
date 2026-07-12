---
id: story-delivery-log-room-id-correlation
kind: story
stage: done
tags: [pi-extension, observability, bug]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-10
updated: 2026-07-10
---

# Delivery log: correlate every event to its `room_id`

## Brief

The extension's delivery debug log (`~/.pi/remote/debug/delivery.log`, gated
behind `REMOTE_PI_DEBUG_LOG=1`) is the third leg of cross-side observability —
it captures the phone→Pi delivery path keyed by message `id`. But it records
**no `room_id`** on any event. Since the log is **shared across all rooms/cwds**
(it lives at `~/.pi/remote/debug/delivery.log`, based on `homedir()`, not
per-cwd), every event from every room is interleaved in one file with no way
to tell which room a `session_lifecycle` / `msg_delivered` / `message_api_armed`
event belongs to.

This blocked the session-divergence diagnosis (2026-07-10): the phone's
messages delivered to sessions `1171ab68` then `7de360ce`, but the shared log
couldn't confirm whether those were patchbay sessions or remote_pi sessions —
the operator had to confirm "the agent wrote files to the patchbay project"
from the filesystem instead. Adding `roomId` to every delivery event makes the
log self-correlating: a single `grep` answers "which room did this message
deliver to" and "which room is this session in."

## Why this is a story, not a feature

This is a focused instrumentation addition — one field on existing events, no
new behavior, no design decisions. The delivery log already exists and is
gated; this just makes it room-aware.

## Design

### Add `roomId` to the delivery event types

In `pi-extension/src/session/delivery_debug_log.ts`, add an optional
`roomId?: string` field to every event variant that carries session/message
context. Optional (not required) so the no-op default and any call site that
doesn't have it degrade gracefully (the field is absent, not an error).

Events to annotate (all of them — every event should be self-correlating):
- `msg_received` — `roomId?: string`
- `wake_outcome` — `roomId?: string`
- `msg_delivered` — `roomId?: string`
- `delivery_pending` — `roomId?: string`
- `queue_drained` — `roomId?: string`
- `queue_dropped` — `roomId?: string`
- `message_api_armed` — `roomId?: string`
- `message_api_null` — `roomId?: string`
- `session_lifecycle` — `roomId?: string`
- `command_ctx` — `roomId?: string`

`roomId` is the 12-char base64url room id (from `roomIdFor`/`_myRoomId`), not
the cwd path — it matches what the relay logs and what the mobile debug log
uses, so all three sides correlate on the same key.

### Thread `roomId` to every call site

**`pi-extension/src/index.ts`** — `_myRoomId` (module-level, line 214) is in
scope at every delivery-log call site. Add `roomId: _myRoomId ?? undefined` to:
- `msg_received` (line ~2375)
- `wake_outcome` (line ~2244)
- `msg_delivered` (line ~2260)
- `delivery_pending` (line ~2309)
- `queue_drained` (line ~2349)
- `queue_dropped` (lines ~2296, ~2327, ~2337)
- `session_lifecycle` (line ~1644, the `onSessionLifecycle` callback)

**`pi-extension/src/session/sdk_session_projection.ts`** — the projection
emits `message_api_armed`, `message_api_null`, and `command_ctx` via
`this.opts.outputs.deliveryDebugLog`. The projection doesn't currently know
its room id. Two options:
- **(a)** Thread `roomId` into `SdkSessionProjectionOptions` at construction
  (the projection is created once per extension instance; `_myRoomId` is set
  before the first `bindApi`). Cleanest — the projection owns its room.
- **(b)** Add a `setRoomId(roomId)` method on the projection (mirrors
  `setDeliveryDebugLogForTest`), called from `index.ts` when `_myRoomId` is
  set (line 1931). Avoids changing the constructor signature.

Prefer **(a)** if the projection is constructed after `_myRoomId` is set;
fall back to **(b)** if construction ordering makes (a) awkward. Decide at
implement time by checking the construction site.

### Privacy

`roomId` is the 12-char hash, not the cwd path — it's already logged by the
relay and the mobile debug log. No new privacy surface. The existing
`FORBIDDEN_KEYS` scrub and `MAX_FIELD_LEN` cap apply unchanged.

## Acceptance Criteria

- [ ] Every `DeliveryDebugEvent` variant carries an optional `roomId?: string`.
- [ ] Every call site in `index.ts` passes `roomId: _myRoomId ?? undefined`.
- [ ] The `sdk_session_projection.ts` events (`message_api_armed`,
  `message_api_null`, `command_ctx`) carry the room id.
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  green (pi-extension).
- [ ] Existing delivery-log tests still pass (the field is optional, so no
  assertion changes required — but verify the serialization includes `roomId`
  when present and omits it when absent).
- [ ] A new or updated test asserts `roomId` appears in a serialized
  `msg_delivered` event when set.

## Out of scope

- Per-room delivery log files (one file per cwd). The shared file + `roomId`
  field is sufficient for correlation and avoids filesystem-state-per-cwd
  complexity. A per-room split is a separate concern.
- The mobile debug log already records `room` on its events — no app change.
- The relay log already records `room` on `authenticated`/`room_meta_update` —
  no relay change.
- The actual session-divergence fix (`feature-session-stable-message-delivery`)
  — this story is the diagnostic that grounds it.

## References

- `pi-extension/src/session/delivery_debug_log.ts` — the event types + serializer.
- `pi-extension/src/index.ts:214` — `_myRoomId` (module-level room id).
- `pi-extension/src/index.ts:1644,2244,2260,2296,2309,2327,2337,2349,2375` —
  delivery-log call sites.
- `pi-extension/src/session/sdk_session_projection.ts:142,152,311,316,336,339,820` —
  projection delivery-log call sites.
- `pi-extension/src/rooms.ts` — `roomIdFor` (the 12-char derivation).
- The blocked diagnosis: phone messages delivered to sessions `1171ab68` /
  `7de360ce` in a shared log with no room correlation (2026-07-10).
