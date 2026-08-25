---
id: story-evidence-stale-ctx-repro-2026-07-09
kind: story
stage: done
tags: [pi-extension, bug, observability, research]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-09
updated: 2026-07-11
evidence_capture: 2026-07-09
---

# FIRST EVIDENCE-GROUNDED stale-ctx repro capture (2026-07-09)

## What this is

The first live capture of the stuck-state failure WITH the observability
instrumentation in place — and it reveals that the `delivery_pending`
tolerance layer (shipped `story-stale-ctx-recoverable-delivery-tolerance`)
did NOT fire on either failure. This contradicts the assumption that the
tolerance layer covers the stuck-state UX. It does not — at least not on
these two repros.

## The two captured failures

Both were operator-sent phone messages that scarred `send_timeout` ("not
delivered") with **no `delivery_pending` signal** and **no echo**.

### Failure 1: `cli_019f4488` — the stale-throw signature (Patchbay)

- **Console line (operator-captured):**
  `[remote-pi] app user_message id=cli_019f4488-e579-7219-a4a1-9ab47dbf72fa:
  recoverable wake failure (not delivered to this pi): This extension ctx is
  stale after session replacement or reload. Do not use a captured pi or
  command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or
  ctx.reload()...`
- **Phone ring log** (`debug/b90-...bin`): `msgSend` 01:40:50.213 →
  `msgFailed` 01:41:10.203 (`send_timeout`, "no echo in 20s"). Room
  `SF_DCbXsmreE` (Patchbay). **No `delivery_pending` event.**
- **Relay log**: the relay saw Patchbay (`l2X/dUc=` on `SF_DCbXsmreE`)
  actively running turns (working flips) but **zero lines in the 01:40:50
  window** — the phone's message reached the relay/extension but the
  extension threw stale and silently dropped it (no echo).
- **Extension delivery log**: **ABSENT** — Patchbay's pi process
  (pid 3690042, started Jul 8 01:46) loaded the **OLD `dist/`** (rebuilt
  15:24 Jul 8 — *after* the process started). So Patchbay has neither the
  `delivery_pending` tolerance code NOR the delivery-path log.
  `REMOTE_PI_DEBUG_LOG` is also unset on that process.

### Failure 2: `cli_019f46d4` — the null-`messageApi` signature (Skills)

- **Console line (operator-captured):**
  `[remote-pi] app user_message id=cli_019f46d4-9c90-7116-9af0-0b827c74b175:
  recoverable wake failure (not delivered to this pi): agent session not
  bound yet`
- **Phone ring log** (`debug/b37-...bin`): `msgSend` 12:22:46.713 →
  `msgFailed` 12:23:06.683 (`send_timeout`). Room `k0H-7lFh371e` (Skills
  session). **No `delivery_pending` event.**
- **Relay log**: phone disconnected 12:22:02, re-authed 12:22:11, then
  `room_meta_update` on `k0H-7lFh371e` at 12:22:46. Phone connection flapping
  around the failure.
- **Extension delivery log**: **ABSENT** — the Skills pi process
  (pid 1134073, started Jul 9 07:00) loaded the **NEW `dist/`** (has the
  tolerance code) BUT `REMOTE_PI_DEBUG_LOG` is **unset** on it, so no
  delivery-path log. AND the `delivery_pending` tolerance did not fire
  despite the new code being loaded → see open question below.

## The two-error sequence — CONFIRMED LIVE

The `story-fix-stale-ctx-messageapi-rearm-on-reload` corrected root cause
predicted a two-error sequence: stale-throw → `forget()` nulls `messageApi`
→ next message gets "agent session not bound yet". **Both errors were
captured live this session** (failure 1 = stale-throw, failure 2 =
not-bound-yet), on two different sessions (Patchbay, Skills). This is the
first live confirmation of the predicted sequence.

## The critical open question (NEW — not previously known)

**Why did `delivery_pending` NOT fire on failure 2 (Skills, new dist)?**

The Skills process (pid 1134073) started Jul 9 07:00 — *after* the `dist/`
rebuild (Jul 8 15:24) — so it HAS the tolerance-layer code
(`story-stale-ctx-recoverable-delivery-tolerance`, committed `cadf2ff` +
`8a8c058`). The console line shows `recoverable wake failure (not delivered
to this pi): agent session not bound yet` — which is the recoverable path
that the tolerance layer was supposed to convert from silent-drop to
`delivery_pending`. But the phone scarred `send_timeout` with no
`delivery_pending`.

Possible explanations to investigate:
1. **The tolerance layer's recoverable detection didn't match this path.**
   The `wakeAgent` returns `{ok:false, recoverable:true, detail:"agent
   session not bound yet"}` for null `messageApi`. The tolerance code in
   `_deliverUserMessage` checks `wake.recoverable` and should enqueue +
   send `delivery_pending`. If it didn't fire, either the recoverable flag
   wasn't set, or the enqueue path failed, or the `delivery_pending` was
   sent but the phone (fresh APK) didn't disarm the timer.
2. **The phone didn't process `delivery_pending`** even if the extension
   sent it. The fresh APK has the app-side `delivery_pending` handler
   (`sync_service.dart`), but maybe it didn't disarm the 20s timer for
   this case.
3. **The `delivery_pending` signal was sent but lost** in the connection
   flap (phone disconnected 12:22:02, re-authed 12:22:11, message at
   12:22:46 — the connection may have been unstable).

**This needs the extension delivery log on the Skills process to answer.**
Until a failure is captured WITH `REMOTE_PI_DEBUG_LOG=1` on the failing
process, we can't see whether `delivery_pending` was emitted. The
observability is deployed but was NOT enabled on either failing process.

## What this changes vs. the prior story framing

The prior story (`story-fix-stale-ctx-messageapi-rearm-on-reload`) assumed
the shipped tolerance layer (`story-stale-ctx-recoverable-delivery-
tolerance`) covered the stuck-state UX ("replaces a silent 20s timeout with
a `delivery_pending` bubble"). **This capture shows that assumption is
unverified** — on the one repro that SHOULD have had the tolerance code
(Skills, new dist), the 20s scar still appeared. The tolerance layer may
not be working as intended, OR the phone-side handler isn't disarming, OR
there's a path it doesn't cover. This is a new finding that reopens the
tolerance story's "done" status for the live-behavior claim.

## Root cause status

The stale-ctx stuck-null root cause (from
`story-fix-stale-ctx-messageapi-rearm-on-reload`'s corrected analysis)
remains the best-supported explanation, now **confirmed live** by the
two-error sequence. The self-heal remains SDK-blocked. BUT the tolerance
layer's live behavior is now in question — it was supposed to mitigate
the UX and didn't.

## Evidence artifacts

- Phone ring logs: `debug/b37-11f1-91a9-9bf5b0bb539b.bin` (Skills failure),
  `debug/b90-11f1-91a9-9bf5b0bb539b.bin` (Patchbay failure).
- Relay logs: `/data/logs/relay.log.2026-07-09` (in the relay container
  volume).
- Console lines: operator-captured (the two `[remote-pi] app user_message
  id=...` lines above).
- Extension delivery log: **ABSENT for both failures** (neither process had
  `REMOTE_PI_DEBUG_LOG=1`).

## Next steps

1. **Enable `REMOTE_PI_DEBUG_LOG=1` on the sessions that fail** (Patchbay,
   Skills) — restart them with the env var. Wrinkle: shared log path
   (`~/.pi/remote/debug/delivery.log`) — two instrumented sessions write to
   the same file. Namespace by cwd/pid before running both instrumented.
2. **Reproduce + capture with the delivery log ON** — then grep the
   message id across all three logs to see whether `delivery_pending` was
   emitted. This answers the critical open question above.
3. **Reopen `story-stale-ctx-recoverable-delivery-tolerance` for the
   live-behavior claim** — the "done" status asserted the tolerance works;
   this capture shows it didn't fire on a real repro (modulo the
   instrumentation gap on the failing process). Verify before trusting.
4. **Patchbay is running stale `dist/`** — restart it to pick up the
   tolerance + log code (it's been running since Jul 8 01:46, before the
   rebuild). This alone may resolve the Patchbay failures.

## References

- `story-fix-stale-ctx-messageapi-rearm-on-reload` (the self-heal,
  SDK-blocked, corrected root cause).
- `story-stale-ctx-recoverable-delivery-tolerance` (the tolerance layer —
  "done" but live behavior now in question).
- `feature-cross-side-observability` (done — the instrumentation that made
  this capture possible, though it wasn't enabled on the failing processes).
- `SESSION-NOTE-2026-07-08-observability-complete-deployed-stale-ctx-
  disambiguated.md` (handoff note — the disambiguation + what's live).

## Closure (2026-07-11)

Superseded by the verified root-cause correction. This evidence capture's open
questions are PARTIALLY answered:

- The "critical open question" (does the tolerance layer cover the stuck
  state?) is resolved at the root-cause level: the stuck state's actual cause
  is the child-`AgentSession`-factory overwriting the parent's `messageApi` —
  verified 2026-07-11 via real-SDK probes + the live delivery log + four
  parallel deep investigations (see the feature's "Corrected root cause"
  section). That root cause is now fixed by the `RemotePiRuntimeCoordinator`
  (`story-fix-stale-ctx-messageapi-rearm-on-reload`, done).
- The "Next steps" (enable debug logging, reproduce with logs on, restart
  Patchbay) were investigative scaffolding toward that root cause, which is
  now fixed.

**Distinct question left open:** this capture observed that the
`delivery_pending` tolerance signal did NOT fire on either repro (neither
process had `REMOTE_PI_DEBUG_LOG=1`). Finding the root cause does NOT explain
*why* the tolerance signal didn't fire on those specific repros — that is a
separate question about the tolerance-path's live behavior, distinct from the
root-cause investigation. It remains unresolved: the tolerance layer is a
mitigation (keeps the phone from a permanent `internal_error` during transient
gaps), and whether it fired correctly on those two repros was never
re-verified with instrumentation on. The coordinator root-cause fix makes this
less load-bearing (the stuck state shouldn't recur), but the tolerance-path
live-behavior question is not closed by the root-cause fix. If the operator
re-observes a stuck state with `REMOTE_PI_DEBUG_LOG=1` after the coordinator
is live, re-open this.

No further action on this evidence item as a root-cause investigation. The
durable conclusions live in `feature-session-stable-message-delivery.md`
(corrected root cause) and the coordinator story.
