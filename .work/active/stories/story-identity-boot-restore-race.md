---
id: story-identity-boot-restore-race
kind: story
stage: drafting
tags: [app, security, bug]
parent: null
depends_on: []
release_binding: null
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

## Blocker
- The required full command `flutter test --exclude-tags e2e --concurrency=2` did not complete green in the concurrent working tree. It reported two behavior failures in `app/test/data/sync/sync_service_test.dart` while another app worker had dirty edits in the same sync/transcript surface; each reproduced green when rerun serially. The two PairingPage widget tests also failed to start with Flutter harness errors (`Bad state: Cannot close sink while adding stream`) and timed out before assertions. This is an environment/concurrent-worker verification blocker, not waived as a product pass; rerun the required full suite after the app worker settles and the Flutter test harness is healthy.
