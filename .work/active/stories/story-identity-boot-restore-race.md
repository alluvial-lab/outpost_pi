---
id: story-identity-boot-restore-race
kind: story
stage: done
tags: [app, security, bug]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-07-27
updated: 2026-08-26
---

# Fresh-install identity boot generates before the Block Store restore lands

Surfaced 2026-07-26 (phone wipe incident): after a reinstall, the first boot
ran before Google Block Store delivered the backed-up Owner identity.
`load()` legitimately returned null → the bridge treated it as first run and
generated a NEW identity. When the restore later arrived, the watch saw a
different Owner key and the transition machinery (working exactly as
designed) wiped pairings + transcripts to adopt the restored key. Operator
lost a day of app state to an avoidable cause.

The v0.3.0 hardening covers "restore races the save" (conditional re-read
before save) but not "restore is merely late" — nothing distinguishes
"no identity exists" from "identity exists but hasn't synced yet."

## Direction
Distinguish restore-pending from genuine first run at identity boot: e.g.
the platform store signals restore completion (or a bounded await of the
first sync event on a fresh install before generating), so a delayed restore
never triggers a generation-then-transition cycle. Investigate
`outpost_pi_identity` plugin semantics for Block Store/Keychain restore
timing first. Related: `feature-owner-identity-transition`,
`gate-security-identity-store-fatal-read-rotates-owner-key` (shipped),
`gate-security-stopped-app-owner-replacement-undetected` (shipped).

## Implementation notes
- Execution capability: inline current-session implementation; app identity boot race with platform-specific restore behavior and deterministic unit coverage.
- Review weight: standard (source: caller default); bounded inline code review completed, but closure is held by the documented full-suite blocker below.
- Files changed: `app/lib/pairing/owner_identity_bridge.dart`, `app/test/pairing/owner_identity_bridge_test.dart`, `app/test/ui/pairing/pairing_viewmodel_test.dart` (test helper uses zero grace for already-local in-memory identities).
- Tests added/removed: late event restore and silent polling restore tests; existing first-run test uses zero grace to remain deterministic.
- Simplification: no plugin API or native change was invented; the bridge uses the existing `watch()` surface plus bounded `load()` polling. Android Block Store has no restore-complete/live-change signal, while iOS exposes foreground/event polling behavior.
- Discrepancies from design: the platform cannot distinguish genuine first run from a late Android restore, so boot now waits up to 3 seconds (200 ms polling) before generation, then retains the existing final read-before-save race fence.
- Adjacent issues parked: none.
- Verification: `flutter analyze` passed; targeted owner-identity suite passed (15 tests, `--concurrency=2`); targeted sync regressions passed serially after the full-suite collision.

## Regression repair (2026-08-26)
- Worktree-based bisect identified `a9f78539`: the new zero-grace test configuration still entered `_awaitLateRestore()`, installed an in-memory watch, and polled under the widget-test async harness instead of bypassing restore waiting. The PairingPage `pair_ok` repro timed out after 10 minutes before the repair.
- A non-positive restore grace now returns before installing a watch, poll, or timer. The PairingPage helper also seeds its in-memory store with a valid Owner identity, matching its documented already-booted fixture contract. The production 3-second event/poll grace and final read-before-save fence are unchanged.
- Regression coverage now asserts that zero grace performs only the initial read and final read-before-save fence (two loads) and never subscribes to `watch()`.
- Targeted evidence: both PairingPage widget tests passed in 4 seconds (2 tests), and the complete Owner identity bridge suite passed (15 tests), including late event restore, silent polling restore, and read-before-save coverage. `flutter analyze` passed with no issues.

## Prior blocker (resolved)
- The required final full-suite gate remains red, so this story stays `stage: implementing`. With the parallel review worker's stale Flutter process gone and this final tree, an exact `flutter test --exclude-tags e2e --concurrency=2` run reached the end with 975 passes and one load-sensitive behavior assertion failure in `sync_service_test.dart` (`clearActiveSession resets the in-memory turn state`). Its exact serial rerun passed, as did earlier serial reruns of the two original sync failures, but the required concurrent command itself is not green and is not waived. The PairingPage hang is resolved and no longer contributes to the blocker.

## Closure (2026-08-26)
- Review verdict: PASS; production boot retains the bounded 3-second restore grace, silent polling/event restore paths, final read-before-save fence, and zero-grace deterministic bypass used by already-local test fixtures.
- Stage: `done`.
- Focused verification: `test/pairing/owner_identity_bridge_test.dart` — 15/15 passed; PairingPage pair-flow tests — 2/2 passed in `test/ui/pairing/pairing_viewmodel_test.dart`.
- Shared full-suite evidence: `flutter test --exclude-tags e2e --concurrency=2` — 976/976 passed on the quiescent machine (commits `cfa060b5..64614030`; the earlier PairingPage hang was fixed in `7000f226`).
- Unmet acceptance criteria: none. No platform restore-complete API was invented; the documented bounded-grace fallback remains the intended implementation.
