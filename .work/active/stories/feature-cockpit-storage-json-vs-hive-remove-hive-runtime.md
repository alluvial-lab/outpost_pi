---
id: feature-cockpit-storage-json-vs-hive-remove-hive-runtime
kind: story
stage: implementing
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

- [ ] Normal startup/composition has no Hive boxes, locks, or API; the only
      `package:hive` import is the legacy migrator.
- [ ] Settings still load before the first frame; window bounds and all four
      repository surfaces restore and persist through `StateStoreFactory`.
- [ ] Requested app exit drains pending stores, and bootstrap failures still
      render `BootstrapErrorApp`.
- [ ] Obsolete Hive retry tests are removed without weakening terminal crash or
      bootstrap-error coverage.
- [ ] Cockpit `flutter analyze` and `flutter test` pass with the repository
      toolchain.
- [ ] `cockpit/CLAUDE.md`, the Cockpit stack skill, `docs/ARCHITECTURE.md`, and
      `docs/SPEC.md` describe atomic JSON as current Cockpit persistence.

## Ordering constraint

Depends on both migration and repository-adapter checkpoints; it is the only
checkpoint that removes old files and changes composition/package surfaces.
