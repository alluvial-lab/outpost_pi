# SESSION NOTE — 2026-07-30 — gate-drain (Track 1 + Track 2) + working-flag + pairing incident

**Status: drained, designed, implemented, and paired. App is live and sending.**

## TL;DR

Big productive session. Drained 28 standalone gate stories (Track 1), designed +
implemented 4 features / 14 child stories (Track 2), fixed the stuck-"working"
bug, and then fought a multi-hour pairing incident chain that turned out to be
five distinct problems stacked. App is now paired and sending correctly.

## Track 1 — drain 28 standalone gate stories → done

Promoted 28 parked low/medium gate findings from `.work/backlog/` to
`stage: implementing` across 4 component workers (pi-extension, relay, app,
cockpit), then drained them through bounded inline review → done. All component
suites green:

| Component | Stories | Suite |
|---|---|---|
| pi-extension | 15 | 942 → 950 (+8 tests) |
| relay | 6 | 225 (fmt + clippy clean) |
| app | 5 | 854 |
| cockpit | 3 | 269 |
| tools/protocol-codegen | 1 (re-dispatch) | 7 |

4 stories initially blocked because the pi-extension worker's fix actually
required edits in `app/`/`cockpit/`/`tools/protocol-codegen/` — the worker
correctly refused to expand scope. Re-dispatched each to its real component
owner; all landed cleanly.

## Track 2 — 4 features designed + implemented → done

Designed (parallel feature-design workers) then implemented (parallel
implement-orchestrator workers) 4 features / 14 child stories:

- `feature-boundary-typed-decoders` (3 children) — mesh-members DTO,
  cockpit LSP typed boundary, relay config-injected parser.
- `feature-lifecycle-disposal-async-void` (5 children) — awaitable `_goIdle`
  with `Promise.allSettled` drains before relay close, exactly-once auth
  cleanup, owner-ingress rejection observer, self-revoke async detach,
  identity-watcher injector disposal.
- `feature-protocol-contract-discriminator-registry` (5 children) — generated
  `RELAY_CONTROL_DISCRIMINATORS`, binary AEAD documented exception.
- `feature-secure-transcript-key-loss-recovery-ux` (1 child) — blocking
  recovery screen, narrow discard, fail-closed retained.

All 4 at `stage: done`. All component suites green (pi-extension 950, relay 232,
app 863, cockpit 277, codegen 7).

### Notable
- The pi-extension worker bounced 3 protocol-contract stories to drafting when
  it discovered the fixes required editing the codegen (`tools/protocol-codegen/`)
  + scan-rule docs (`.agents/skills/`) — read-only for it. Re-dispatch worker
  with expanded scope completed them.
- The `[refactor]` tag was wrong on the 3 scan-library features (scan libraries
  declare `findings-route: none` — fixes aren't black-box-preserving). Retagged
  so `feature-design` would accept them.

## Retired the live-phone-repro cluster

`epic-targeting-and-session-lifecycle-contracts` arc closed — its observability
thesis self-executed (cross-side observability shipped v0.1.0, resolved 3 of 5
cluster bugs, 2 unreproduced with no recurrence in 3+ weeks). Archived the epic +
feature + 4 resolved/unreproduced stories. Promoted
`story-mobile-transcript-reorder-after-backlog-flush` to standalone (fresh live
observation, stays active).

## working-flag-stuck bug → done (commit `8b987c8`)

App showed pi as "working" while idle. Root cause: the SDK `session_shutdown`
handler in `composition_root.ts` stopped the relay + cleared stale contexts but
never converged the turn projection — when a replacement/quit fired during an
active turn, terminal `agent_end`/`turn_end` events were dropped on the stale
runner, so `working=true` never published `false`. Fix: `resetTurnSnapshot()`
runs in `disposeRuntimePorts` before `relay.stop()`. Needs a full pi restart
(not `/reload`) to load.

## Pairing UX fixes (3 commits)

- `8603635` — narrow-terminal pair dialog shows the copyable URI (was hidden
  behind the QR width gate).
- `5ff8f2e` — stop silently swallowing pasted pairing codes (parse tolerates
  whitespace/quotes; malformed-but-intentional codes surface a readable error).
- Debug APK rebuilt + sideloaded with both fixes.

## Pairing incident chain (the multi-hour saga)

After the working-flag fix + pi restart, re-pairing failed through 5 stacked
problems:

1. **Stale pairing** — app bound to old pi room after restart. (Expected;
   re-pair needed.)
2. **Narrow terminal hid the URI** — fixed by `8603635`.
3. **"Pairing could not be completed"** — peer-storage lock contention from
   4 pi processes sharing one owner identity. The orphaned patchbay pi
   (PID 1601741, pts/3 unreachable in code-server) held `peers.lock`. SIGTERM
   ignored (stuck in `wait_w` on dead pty); SIGKILL cleared it.
4. **30s timeout** — `O`↔`0` character corruption in the copy-pasted URI
   (terminal font rendered them ambiguously; copied bytes had both swapped).
   Resolved via the file seam (`OUTPOST_PI_PAIR_CODE_FILE=/home/agent/.pi/remote/pair-code.json pi --continue`).
5. **Final pair** — app paired, sent to correct room `83MK6OkhBrcQ`, `msg_delivered`
   to session `773bba50`. Live and sending.

## Parked follow-ups (2 backlog items)

- `idea-pairing-opaque-lock-timeout` — `internal_error` should surface the
  lock-timeout cause; multi-pi-shared-identity hazard worth doc-ing.
- `idea-pair-code-clipboard-copy` — pair dialog needs a clipboard-copy action
  to eliminate visual transcription of base64url confusables.

## Remaining active queue

- `story-mobile-transcript-reorder-after-backlog-flush` (drafting — fresh live
  observation, concrete repro direction).
- `gate-security-combined-app-verification-flaky` (drafting — app test-isolation
  triage; the combined-run flakes persisted through this session, each file
  green in isolation).

## Deploy notes

- `dist/` is rebuilt with the working-flag fix + pairing UX fixes. Loaded by
  the current pi process (restarted with `--continue`).
- App running the rebuilt debug APK (release keystore not on the VM).
- Patchbay session preserved (8.4M jsonl); resume with
  `cd /home/agent/projects/patchbay && pi --continue`.
- Unpushed: the full session's commits are local on `main`. Push when ready.
