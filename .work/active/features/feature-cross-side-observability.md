---
id: feature-cross-side-observability
kind: feature
stage: drafting
tags: [pi-extension, app, relay, observability, testing]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

# Cross-side observability & session-replacement reproduction (critical path)

## Brief

The single highest-leverage gap in this area, and the critical path for the
whole epic. The epic's reframed thesis is that the boundary bug class exists
because we are observability-blind on the phone (and relay) side where the
bugs manifest — the extension side is already retroactively diagnosable
(`audit.jsonl`), but the phone is only `debugPrint` → logcat (bounded, wiped
on reboot) and the relay is stdout only. Every wrong fix this session (the
`factoryApi` re-arm, the single-process framing) *also* passed its
mock-based tests because the mocks don't model `runtime.assertActive()` or
real SDK session replacement. This feature closes both gaps: the
**observability** that makes live bugs diagnosable after the fact, and the
**harness** that makes mock-only failures reproducible in CI.

## Scope (priority order)

1. **Phone-side persistent ring log** (`idea-cross-side-logging-for-debug`,
   2026-06-29 survey) — the lead child and highest-leverage piece.
   - Bounded in-memory ring buffer flushed to a file on device
     (`getApplicationDocumentsDirectory`), surviving reboot and buffer
     rollover.
   - In-app "Export debug log" share-sheet action.
   - Captures the state-transition lines that map 1:1 to the shipped resilience
     fixes: `working` convergence, room snapshot adoption, reconnect hydration,
     send-failure surfacing, pending-send backstop, stale-session history
     guards, session-gate rejections.
   - `adb logcat -d` remains the zero-setup USB path; the ring log covers the
     non-USB / reboot / buffer-rollover case (the actual failure mode for
     "anecdotal" bugs).
2. **Cross-side correlation key** — the message id is already shared between
   app (`[msg-send] id=…`) and extension (`app user_message id=…`). Extend it
   onto the relay forward path (`pi_forward`) so one id greps across all three
   sides. Confirm the `session_started_at` high-water as a secondary
   correlation key.
3. **Relay persistent logging** — optional file sink for `tracing` (stdout
   remains default; gate behind an env flag / container volume). The relay's
   stdout is gone on scroll/restart unless redirected at launch; a file sink
   makes the relay side match the extension's retroactive capability. Add a
   `debug!` on the forward path with `peer`, `room`, and message id so silent
   drops become visible without INFO spam.
4. **Transport-frame observability** (`story-add-transport-frame-observability`,
   parked) — privacy-safe, throttled diagnostic surface for dropped/malformed
   relay and peer-channel frames.
5. **Session-replacement integration harness** — drives a real
   `ctx.newSession()` / `/reload` / `/resume` / fork through the actual SDK
   `ExtensionRunner` and asserts post-replacement: message delivery works,
   history replays, app actions land on the fresh ctx, no stale-ctx throw
   reaches the wire. This is the test-side analog of the ring log — it makes
   the mock-only failures reproducible in CI instead of only in live use.
   If genuinely infeasible against the installed SDK, document exactly why and
   ship an honest xfail + the ring log as the diagnostic substitute.

## Why this is a feature, not a story

The ring log has open design decisions (retention/rotation policy, what's
release-safe to surface vs debug-mode-only, share-sheet format, privacy
scrubbing of payloads). The relay file sink has container/deploy implications
(volume mount, the live `remote-pi-relay` Docker container's stdout today).
The harness is design-bearing — building it against the installed SDK requires
figuring out how to drive the real `ExtensionRunner` from a vitest, which may
surface SDK constraints. All five are force-multipliers for the epic, not
one-line fixes.

## Unblocks

- Honest verification of every code fix under
  `epic-targeting-and-session-lifecycle-contracts`.
- Attribution of the reconnect cluster (`feature-reconnect-reproduction`).
- The `#2` stale-error repro (becomes reproducible instead of anecdotal).
- Rapid diagnosis of future boundary bugs (the instrumentation that would have
  caught this session's wrong premises earlier).

## Out of scope

- The contract prose (`feature-contract-gap-audit`) — downstream of what this
  finds.
- The reconnect cluster attribution itself (`feature-reconnect-reproduction`).
- The `#2` stale-error repro as a contract item (separate observe-and-diagnose
  task; this feature makes it reproducible, doesn't fix it).

## Open decisions (design time)

- **Ring log:** retention window / size cap; release-safe content (counts vs
  structured events vs debug-mode-only); privacy scrubbing (message bodies,
  session content); share-sheet format (raw jsonl vs rendered text).
- **Relay file sink:** env flag name; container volume path; rotation; whether
  to use `tracing-appender` (non-blocking) or a simpler file writer.
- **Harness feasibility:** can the installed SDK's `ExtensionRunner` be driven
  headless from a vitest? If not, what's the minimal real-SDK seam?
- **Correlation key shape:** message id alone, or message id + `session_started_at`?
  Confirm the app's `user_message id` and the extension's `app user_message id`
  are already identical (survey says yes — `index.ts:3297`).

## Relationship to released bold work

Consumes the generated-protocol codegen (`epic-bold-generated-protocol`,
done) for any new diagnostic frame types. Does not duplicate
`epic-bold-reachability-contract` state-machine work — this feature adds
*instrumentation onto* the reachability states, not new states.
