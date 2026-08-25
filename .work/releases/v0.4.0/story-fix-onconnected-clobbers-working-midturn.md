---
id: story-fix-onconnected-clobbers-working-midturn
kind: story
stage: done
tags: [bug, pi-extension, lifecycle]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-07-30
updated: 2026-08-11
---

# `onConnected` publishes unconditional `working=false`, clobbering a genuine mid-turn state

## Symptom
The `d1117f7` fix (publish `working=false` on session_start + a new `onConnected`
relay-reconnect callback) over-corrected: `onConnected` hardcodes
`_sdkSessionProjection.publishWorking(false)` on every relay (re)connect. If the
relay drops and reconnects while pi is genuinely working (a transient network
blip mid-turn), the callback publishes `working=false` and mutates
`_myRoomMeta.working` to false. The app then renders pi as idle while a turn is
actively streaming — the operator may send a new prompt without `steer`,
believing pi is free, when it is busy.

## Root cause
`pi-extension/src/index.ts` — the `onConnected` callback inside
`_relayTransport.start({ ... })`:

```js
onConnected: () => {
  _sdkSessionProjection.publishWorking(false);  // ← unconditional; wrong mid-turn
},
```

This was added to clear stale `working=true` left by a killed predecessor
process (a real bug), but it fires on EVERY reconnect, including reconnects
during a live turn. The relay's room state for the pi's room is authoritative
to the app, so a false publish mid-turn is visible immediately.

## Fix
Publish the **authoritative projection**, not a hardcoded value:

```js
onConnected: () => {
  _sdkSessionProjection.publishWorking(_turnProjection().working);
},
```

This clears stale `true` from a killed predecessor (whose successor starts idle
→ projection is `false`) while preserving a genuine `true` during a
reconnect-mid-turn.

## Verification
- Add a contract test: relay reconnects while `working=true` (turn active) →
  `onConnected` must republish `true`, not `false`.
- Existing tests that `mockClear()` after connect must still pass (the connect-time
  publish becomes the projection's current value, which is `false` at idle
  startup — same observable frame).
- `composition_root` session_start publishWorking(false) is unaffected (that path
  fires before relay connect and is a no-op; `onConnected` is the real clear path).

## Out of scope
The broader hot-reload restart mechanism (blockers 2-4 from the adversarial
review) is tracked in `feature-extension-hot-reload-via-process-restart`. This
story is just the working-flag regression in already-shipped code.
