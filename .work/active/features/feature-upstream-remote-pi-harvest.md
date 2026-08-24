---
id: feature-upstream-remote-pi-harvest
kind: feature
stage: done
tags: [pi-extension, app, relay, cockpit]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-16
---

# Upstream remote_pi harvest — 2026-08 divergence sweep (459 commits)

Sweep executed 2026-08-15 against `upstream/main` @ 8fa8df8b (import point:
`02b2c92`, cockpit 1.5.1 → upstream 1.26.0+60). Applicability verified
per-candidate against our tree by a source-read pass; four load-bearing
claims re-verified by the orchestrator before item-writing.

## Posture

- **Cockpit is in use** (operator decision 2026-08-15, revising the earlier
  "public-artifact only" stance). Crash-class cockpit ports are first-class
  stories; deferred L-cost items carry explicit promote triggers.
- **Harvest, never merge**: wholesale upstream-cockpit adoption is not an
  option — our cockpit is wire-locked to our extension via the paired
  control-RPC contract (`\x00outpost-pi-ctrl:`, hard cutover, AGENTS.md),
  brand-locked to Phosphor Beacon, and carries our lifecycle/generated-
  contract work. Upstream features are evaluated per-subsystem as
  integration projects (see backlog-upstream-cockpit-feature-subsystems).
- **Not adopted** (recorded so future sweeps skip them): i18n/slang (English
  fine), multi-theme system + JSON import (conflicts with the Phosphor
  Beacon single-contract), navigator webview, DB panels, Copilot
  integration, sounds.

## Disposition of 28 candidates

- **FIXED-OURS (8)** — our arc already solved them: stale-ctx relay-state
  crash (`52b6cef0`), session_start binding (`922eb57c`), legacy/explicit
  room routing (`8d5b0003`/`7fda0f90`), canonical cross-PC routing
  (`846042a9` — our to_room + domain-separated auth is the divergent,
  deliberate solution), mesh-name/session decoupling (`3dc880cd` et al.),
  cockpit settings NPE (`55037fdb`), + others. Validation, not work.
- **REFERENCE (1)** — `fc2339bd` concurrent-startup coalescing: note added
  to `gate-tests-concurrent-first-run-pairing-race` (our production
  coalescing exists at `index.ts:1877-1892` + exclusive identity creation;
  the story's tests must prove it).
- **INAPPLICABLE (6)** — upstream-only architecture (Ghostty teardown,
  WorkspaceMenuBridge, worktree watcher rearm, Windows close-dialog,
  read-only-fs name-sync, stale name-sync).
- **PORT (13)** — 7 stories + 2 deferred-with-trigger backlog items below.

## Stories (all independent, no depends_on)

1. `story-harvest-extension-robustness-ports` — keyring timeouts, non-fatal
   keyring load, file-first identity precedence, print-mode relay guard
   (upstream `a60526ec`, `074c5c5f`, `f6a92d86` half, `964c9005`).
2. `story-harvest-app-session-robustness-ports` — same-peer reconnect room
   preservation (`c7105191`), iOS ubiquity-gate unblocking (`535a5a0e`).
3. `story-harvest-app-working-idle-reconciliation` — authoritative-idle
   beats stale `transcript.working` (`12ef2956`), ported into the canonical
   projection model.
4. `story-harvest-mesh-ingress-queueing` — queue Pi-to-Pi mesh messages
   between runs (`56a73d9d`), integrated with SdkSessionProjection lifecycle.
5. `story-harvest-relay-overlapping-owner-auth` — authorize against the
   union of matching owners, not first match (`614f4e36`).
6. `story-harvest-cockpit-crash-class-ports` — deleted-workspace recovery
   (`8d40daf7`) + bounded Hive-open retry (`a0af1dd8` half).

## Deferred (backlog, with promote triggers)

- `backlog-cockpit-terminal-output-backpressure` (`7b976f5a`/`554750a8`)
- `backlog-cockpit-hive-json-store-migration` (`bbfaa417`)
- `backlog-upstream-cockpit-feature-subsystems` — per-subsystem feature
  evaluations under the cockpit-in-use posture.

## Verification

Each story verifies its port against our architecture (no direct
cherry-picks where our lineage diverged), runs the owning subproject's
command set, and cites the upstream sha in its commit message for
provenance.

## Review record (2026-08-16)

**Standard weight, one independent pass** — fresh-context cross-model
reviewer (gpt-5.6-sol). Verdict: Request changes → **closed done** after
receiver-confirmed blocker fixes (standard policy: no second pass).

- **Blockers (4/4 confirmed by adjudication, fixed + verified):**
  1. Timed-out keyring write racing retries → persisted identity ≠ returned
     identity — fixed in `1b098eb9` (stable candidate per creation attempt +
     serialized raw writes).
  2. Roster mint guard failing open on malformed/unreadable `peers.json` —
     fixed in `1b098eb9` (strict read; only absent/valid-empty permits mint;
     force-escape intact).
  3. Mesh batch discarded before SDK handoff succeeded — fixed in `1b098eb9`
     (retain prefix until success; retry at next settle; stale evicts).
  4. Authoritative idle not clearing stale streaming UI — fixed in `87ea7307`
     (session-keyed streaming suppression; replacement-session streams
     preserved).
- **Important (2): parked unbound** → `gate-review-reconnect-latch-test-hardening`,
  `gate-review-cockpit-bootstrap-wiring-test`.
- **Rejected proposals (2):** relay union cache staleness/poisoning and iOS
  silent-identity-replacement — both unsupported on inspection (reviewer
  self-rejected with evidence; adjudication concurs).
- Post-fix verification: pi-extension typecheck + 994 tests + build green;
  app analyze + 881 tests (concurrency=2) green. Known flakes: extension
  audit-rotation timing under uncapped load, app sync-test isolation — both
  pass focused/isolated; pre-existing, documented in story bodies.

## Implementation summary (2026-08-16)

All 6 child stories completed via a 4-worker subproject split (disjoint
write sets, 4 toolchains, memory-constrained VM); orchestrator performed
this roll-up.

| story | commit | verification |
|---|---|---|
| story-harvest-extension-robustness-ports | 476b5b8e | pnpm typecheck + build; 982 tests |
| story-harvest-mesh-ingress-queueing | ad72a547 | pnpm typecheck + build; 985 tests |
| story-harvest-app-session-robustness-ports | c5850ceb | flutter analyze; 878-test suite |
| story-harvest-app-working-idle-reconciliation | 46b61a7c | flutter analyze; focused + full suite |
| story-harvest-relay-overlapping-owner-auth | af9c4abf | fmt + clippy -D warnings; 234 tests |
| story-harvest-cockpit-crash-class-ports | 4f82075f | flutter analyze; 285 tests |

Parked/observed: pre-existing app sync-test isolation flake (passes isolated,
recorded in story body); two extension audit-rotation timing tests flaked once
under full-suite load, passed focused + full reruns (no weakening); local-SDK
`volume_controller` registrant drift left uncommitted (separate chore).
