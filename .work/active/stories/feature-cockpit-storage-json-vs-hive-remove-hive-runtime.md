---
id: feature-cockpit-storage-json-vs-hive-remove-hive-runtime
kind: story
stage: done
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: [feature-cockpit-storage-json-vs-hive-legacy-migration, feature-cockpit-storage-json-vs-hive-repository-adapters]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Cut bootstrap over and remove Hive from the live runtime

## Checkpoint

Complete the parent feature's Unit 4. Run the legacy migration before opening
JSON state, construct one `JsonStateStoreFactory`, load settings/window state
through it, pass that one boundary through `buildAppModule` into
`buildCockpitModule`, and bind the JSON repositories. Add requested-exit
lifecycle ownership that awaits `flushAll()` while retaining the existing
window resize debounce.

Delete the five live Hive helpers/adapters, remove `Hive.initFlutter`, live box
opening/retry, and `hive_flutter`. Retain `hive` only in the one-shot legacy
migrator because installed state is a real compatibility obligation. Add direct
`path`/`path_provider` dependencies and roll Cockpit durable docs from Hive to
atomic JSON plus the isolated migration reader.

The standalone `gate-review-cockpit-bootstrap-wiring-test` is independent. Do
not add a substrate dependency; if its concurrent change is present, preserve
and adapt its storage-neutral bootstrap-error assertion rather than deleting it.
`story-identity-boot-restore-race` is mobile secure-identity work and is not
part of this storage surface.

## Acceptance evidence

- [x] Normal startup/composition has no Hive boxes, locks, or API; the only
      `package:hive` import is the legacy migrator.
- [x] Settings still load before the first frame; window bounds and all four
      repository surfaces restore and persist through `StateStoreFactory`.
- [x] Requested app exit drains pending stores, and bootstrap failures still
      render `BootstrapErrorApp`.
- [x] Obsolete Hive retry tests are removed without weakening terminal crash or
      bootstrap-error coverage.
- [x] Cockpit `flutter analyze` and `flutter test` pass with the repository
      toolchain.
- [x] `cockpit/CLAUDE.md`, the Cockpit stack skill, `docs/ARCHITECTURE.md`, and
      `docs/SPEC.md` describe atomic JSON as current Cockpit persistence.

## Implementation notes

Implemented inline by the feature-owning `openai-codex/gpt-5.6-sol` worker at
`xhigh` effort after both migration and repository checkpoints reached `done`.
The final cutover was intentionally last because it owns the overlapping
bootstrap, package, deletion, and durable-documentation surfaces.

`bootstrapCockpit` now performs native preflight, resolves the platform state
path, runs `LegacyHiveMigrator` before any JSON open, constructs one
`JsonStateStoreFactory`, loads settings and window bounds before the first
frame, and passes that same factory through `buildAppModule` and
`buildCockpitModule`. The Cockpit module opens projects, layouts, and the shared
settings store exclusively through that boundary and binds only JSON repository
adapters. A recording-factory composition test proves all feature repository
opens traverse the one injected factory.

The existing storage-neutral `openStore` seam and its bounded retry remain only
on the injected bootstrap-test branch so the independent wiring regression can
exercise exhausted-open handling unchanged. Production JSON startup does not
use the old live-box lock retry. The obsolete generic Hive helper, four live
Hive repository adapters, their two implementation-bound retry tests,
`Hive.initFlutter`, and `hive_flutter` were removed. `package:hive` appears in
exactly one production file: the marker-last legacy reader.

Window resize persistence now uses one state-store `putAll` batch. A
`StateStoreExitObserver`, owned alongside the window listener, awaits
`flushAll()` before approving a requested app exit; its lifecycle wait is
covered with an explicit release barrier. Bootstrap exceptions still unwind
into `BootstrapErrorApp`.

Durable Cockpit guidance, stack reference, core/module references, README,
ARCHITECTURE, and SPEC now describe versioned atomic JSON, quarantine recovery,
Application Support placement on Windows, lifecycle flush ownership, and Hive's
strictly isolated compatibility-reader role. Backend-specific live-Hive
comments were removed from code.

Unrelated concurrent Cockpit theme-contract test edits and pre-existing
generated plugin registrant changes were preserved in the working tree and
excluded from this item's commit.

## Verification

From `cockpit/` with the repository Flutter SDK and `PUB_CACHE`:

- Exact staged-state isolation (detached worktree with only this item's patch):
  `flutter analyze` passed with zero issues and `flutter test` passed all 313
  tests.
- The combined working tree also passed all 314 tests, including an unrelated
  concurrent theme-contract test that remains unstaged.
- `test/storage_composition_test.dart` proves one supplied factory opens
  `projects`, `layouts`, and shared `settings` during app composition.
- `test/core/data/state_store_lifecycle_test.dart` proves an exit response does
  not complete until `flushAll()` completes.
- `test/domain/crash_recovery_test.dart` retains terminal crash and bootstrap
  error coverage. The named bootstrap wiring test body/assertions were not
  modified; it passed unchanged and still proves exhausted store opens render
  `BootstrapErrorApp` without an unhandled throw. Only the two obsolete
  Hive-helper unit tests and import were deleted.
- Source/dependency sweeps confirm no `hive_flutter`, no live `hive_*` adapter
  files, and exactly one `package:hive` import under `cockpit/lib/` (the legacy
  migrator).

## Ordering constraint

Depends on both migration and repository-adapter checkpoints; it is the only
checkpoint that removes old files and changes composition/package surfaces.
