# Session note — 2026-07-08/09 — observability feature completed + deployed; stale-ctx disambiguated

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## TL;DR

Started wanting a `/reload` button for the stuck-state mobile lockout. Pivoted
to **closing the observability gap first** (the documented critical path),
because the root cause of the user's symptom was *not actually traced* — I had
conflated two bugs (stale-ctx vs transport room-mismatch). All three
observability legs are now built/deployed/live. The stale-ctx self-heal remains
SDK-blocked and open. **Operator is switching machines; resume from "fully
armed for next repro."**

## What actually happened (the important turn)

1. Operator reported the stuck-state symptom: phone "not delivered" →
   workstation `/reload` → recovered. Asked for a `/reload` button.
2. I traced feasibility: `reload()` IS on `ExtensionCommandContext` (not
   SDK-blocked like `sendUserMessage`), but a phone button would hit a null
   `commandCtx` in the exact stuck state (same class of gap as `messageApi`).
3. **I wrongly pivoted to the transport room-mismatch bug** (found a
   `room-mismatch` storm in `debug/ae8-*.bin`) and asserted the symptom was
   transport, not stale-ctx. **Operator corrected me**: the `/reload`-recovery
   is the tiebreaker — transport wouldn't be fixed by `/reload`, stale-ctx
   would. I was wrong; the failure IS stale-ctx.
4. Root cause of MY confusion: phone ring logs can't see the workstation
   half (`messageApi` state, `/reload`). I was inferring the workstation side
   and presenting it as findings.
5. **Operator redirected: close the observability gaps first.** We did.

## The bug disambiguation (load-bearing for next steps)

**Two bugs share the same phone symptom (`send_timeout` "not delivered"):**

- **Stale-ctx null-wall** (`story-fix-stale-ctx-messageapi-rearm-on-reload`,
  `stage: drafting`, **SDK-blocked**): after `/new`/`/resume`/`/fork`,
  `messageApi` goes null via `forget()` and nothing re-arms it except a
  `/reload` (the only factory re-invoke). `commandCtx` is ALSO null there
  (plain `session_start` doesn't rebind it). The self-heal needs an upstream
  ask: expose `sendUserMessage`/`reload` on the plain `session_start` ctx, OR
  make `/new`/`/resume`/`/fork` re-invoke the factory. **Recovery signature:
  `/reload` fixes it.** This is the bug the operator hit.

- **Transport room-mismatch** (`story-mobile-send-timeout-relay-room-main-
  mismatch`, `stage: drafting`, fix `ca555be` in source — **now deployed** in
  the fresh APK): app's `WsTransport._activeRoom` stuck on the wrong relay
  room. `room-mismatch` drops in the ring log. **Recovery signature: `/reload`
  does NOT fix it** (app-side state). Distinct from stale-ctx.

The fresh APK (built + sideloaded this session) deploys the transport fix +
the `delivery_pending` tolerance layer, so a future repro that *still* fails
after `/reload` is confirmed stale-ctx (the SDK-blocked one).

## What shipped this session

### `feature-cross-side-observability` → DONE (all 7 units + companions)

The feature's 3 legs of cross-side correlation are now all present:

| Leg | Status | Where |
|---|---|---|
| Phone ring log (Units 1-4) | ✅ done (prior) | app `debug/*.bin` export |
| Relay file sink + `env_id_tail` (Unit 5) | ✅ done + **deployed** | `remote-pi-relay:0.2.2`, `REMOTEPI_RELAY_LOG_DIR=/data/logs`, `RUST_LOG=info,relay=debug` |
| Extension delivery-path log | ✅ done + **built** (this session) | `~/.pi/remote/debug/delivery.log`, `REMOTE_PI_DEBUG_LOG=1` |

### `story-extension-delivery-path-ring-log` (the missing third leg) — DONE

The feature's original brief wrongly claimed "the extension side is already
retroactively diagnosable (`audit.jsonl`)" — `audit.jsonl` records cross-PC
mesh routing, NOT the phone→Pi delivery path. This story closed that gap.

- New: `pi-extension/src/session/delivery_debug_log.ts` — typed
  `DeliveryDebugEvent` registry (10 variants) + `DeliveryDebugLog` port +
  `DeliveryDebugLogImpl` (bounded ring + file, env-gated, privacy-scrubbed).
- Wired into projection (`bindApi`/`bindCommandContext`/`clearStaleContexts`/
  `forget`/`bindReplacementContext`) + `index.ts` delivery/replay-queue paths
  + `composition_root.ts` `session_lifecycle` emit via new optional
  `onSessionLifecycle` port method (forwarded through legacy ports adapter).
- Cross-model review (`openai-codex/gpt-5.5`, high): Request changes →
  Approve. 3 important findings fixed: (1) warm/dirty duplication + unbounded
  file → removed `warmFromFile`, added `capFile`; (2) missing withSession
  re-arm emit → added to `bindReplacementContext`; (3) untested `index.ts`
  `wake_outcome` path → added test-only accessors + extended null-window test.
- Tests: 805/805 pass (was 769; +36 across the story).
- `dist/` rebuilt.

### Disk-growth bounds (all three logs now bounded)

- **Relay**: added `prune_old_relay_logs()` — `tracing-appender`'s
  `rolling::daily` rotates but does NOT retain (one file/day forever). Added
  14-day retention sweep on startup. Rebuilt + redeployed `0.2.2`.
- **Extension**: tightened `capFile` (byte-accurate keep-from-tail, tested).
- **Phone**: already safe (snapshot-write, 1 MiB cap).

### Fresh APK built + sideloaded

`app/build/app/outputs/flutter-apk/app-release.apk` (80.2 MB, v1.2.0+7).
Sideloaded via `adb push` + `adb shell pm install` (the `-O` flag and direct
`adb install` failed with `splice EINVAL`; `pm install` of the pushed file
worked). Deploys: `delivery_pending` tolerance + transport room-main fix
(`ca555be`) + phone ring log.

## Current live state (for resuming)

- **Relay**: `remote-pi-relay:0.2.2` healthy, file sink + retention + debug
  correlation live. Read: `docker exec remote-pi-relay tail -f /data/logs/relay.log.$(date -u +%F)`
- **This remote_pi pi process**: `REMOTE_PI_DEBUG_LOG=1` set (operator
  restarted this session with it). Delivery log live at
  `~/.pi/remote/debug/delivery.log`.
- **Patchbay pi process**: `REMOTE_PI_DEBUG_LOG` NOT set — its delivery path
  is blind (operator hit a failed message on Patchbay this session; could not
  diagnose — relay saw no drops, agent was alive, but no extension log).
- **Phone (mobile)**: fresh APK deployed. NOT the tablet (tablet isn't paired).
- **Verified end-to-end**: 3+ live messages captured across all legs, all
  `messageApiArmed:true, ok:true` (healthy baseline established). Daily log
  rotation confirmed (rolled 07-08 → 07-09 at midnight UTC).

## Open work / next steps

### The actual stuck-state fix — STILL OPEN, SDK-blocked

`story-fix-stale-ctx-messageapi-rearm-on-reload` (`stage: drafting`,
`feature-session-stable-message-delivery`). The self-heal needs the upstream
ask (expose `sendUserMessage`/`reload` on plain `session_start` ctx, or make
`/new`/`/resume`/`/fork` re-invoke the factory). **Do NOT attempt another
in-fork re-arm fix — the prior `factoryApi` attempt was wrong and reverted
(`runtime.assertActive()` throws stale on the factory `pi` too).**

The observability is now in place to **diagnose the next repro from
evidence**: grep one message `id` across phone `msg-send` ↔ relay
`env_id_tail` ↔ extension `app user_message id` + `messageApi` state. The
extension log will show `session_lifecycle { reason }` precursor +
`message_api_null` window + `wake_outcome { messageApiArmed:false }`.

### Known gaps to address

1. **Patchbay (and other sessions) uninstrumented.** To diagnose failures
   there, restart with `REMOTE_PI_DEBUG_LOG=1`. **WRINKLE: shared log path** —
   multiple instrumented sessions write to the same
   `~/.pi/remote/debug/delivery.log` (same `REMOTE_PI_HOME`). If running two
   instrumented sessions, namespace the path by cwd/pid (not yet done).
2. **`/reload` button** (the original request) — parked at
   `idea-mobile-session-control`. Feasibility: works when `commandCtx`
   happens to be armed (after a slash command), degrades honestly when null.
   Not the real fix (SDK-blocked self-heal is). Revisit after the stuck-state
   root cause is confirmed from logs.
3. **`story-mobile-send-timeout-relay-room-main-mismatch`** — fix deployed in
  fresh APK, but the `DEPLOY + VERIFY` AC is unchecked. Verify: next fresh
  ring log shows zero `room-mismatch` drops.

### Review queue (substrate)

- `story-fix-stale-ctx-wrapactionctx-crash` — `stage: review`
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` — `stage: review`

## Key commits (HEAD = `50a251e`)

- `50a251e` observability: bound all three logs against unbounded disk growth
- `e247db8` work: advance feature-cross-side-observability to done
- `855cd74` work: advance story-extension-delivery-path-ring-log to done
- `5338ec0` implement: address review findings for story-extension-delivery-path-ring-log
- `3b21804` implement: story-extension-delivery-path-ring-log (missing third leg)
- `2dae3fa` work: scope story-extension-delivery-path-ring-log (missing third leg)
- `9908ff0` relay: deploy file-sink observability (0.2.2) + advance story to done

## Agent-reflection note (for honesty)

This session I made a significant wrong turn: I over-weighted a `room-mismatch`
storm I found in the phone ring logs and asserted the operator's symptom was
the transport bug, not stale-ctx. The operator caught it via the `/reload`-
recovery tiebreaker. Root cause of my error: I was inferring the workstation
half from phone-only logs and presenting inference as finding. The
observability work this session is the direct remedy — but the lesson is to
flag epistemic limits (what a log can vs can't see) up front rather than
present reconstructed state as observed. Also: the `feature-cross-side-
observability` brief's claim that `audit.jsonl` covers the extension was
misleading and I repeated it uncritically until I verified `audit.jsonl` is
mesh-routing-only. Verify, don't inherit claims.
