---
id: epic-rebrand-external-surfaces-retire-rp-s3-runtime-update-noop
kind: story
stage: review
tags: [rebrand, app, cockpit]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Make runtime updates no-op without rp-s3

Implement Unit 1 of the parent feature.

## Scope

- In `app/lib/data/update/update_checker_impl.dart`, remove the default
  manifest URL. Keep optional explicit URL injection; with none,
  `fetchLatest()` returns `null` before creating a network request.
- In `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart`, apply the
  same default no-op behavior while preserving `HttpClient` teardown and the
  explicit-URL error/parse behavior.
- In `cockpit/lib/app/cockpit/cockpit_module.dart`, remove `_kDownloadsBase`
  and omit macOS/Windows appcast feeds so `_buildSelfUpdater` chooses the
  existing `NoopSelfUpdater`.
- Update `cockpit/packaging/README.md`: auto-update appcasts are not currently
  published/deployed. Do not retain a rp-s3 publish path.
- Add focused default no-op tests in the conventional app/cockpit update test
  locations and preserve coverage of explicit URL handling where feasible.

## Acceptance criteria

- [ ] Default app and cockpit update checks return `null` without HTTP.
- [ ] Explicit manifest URLs preserve existing parsing and silent failures.
- [ ] Cockpit native self-update has no appcast URL by default.
- [ ] No file in this story retains `rp-s3.jacobmoura.work`.
- [ ] Relevant Flutter tests and `flutter analyze` pass, or an exact
  environmental prerequisite is recorded.

## Implementation notes

- Both update checkers now treat a missing manifest URL as an immediate `null`
  result. The app checker lazily creates its default Dio adapter only after an
  explicit URL is supplied; the Cockpit checker creates and tears down its
  `HttpClient` only for explicit URLs, preserving the existing silent failure
  and parsing paths.
- Cockpit no longer supplies native appcast URLs, so its existing updater
  selection resolves to `NoopSelfUpdater`; the packaging runbook records that
  appcasts are not currently published or deployed.
- The explicit worker instruction restricted edits to the two checker files,
  `cockpit_module.dart`, and the packaging README (plus this required stage
  transition), so no new test files were added despite the broader Scope test
  bullet. Existing update-focused tests were run: app `update_info_test.dart`
  and Cockpit `update_info_test.dart` plus `auto_updater_self_updater_test.dart`
  passed.
- Verification: Cockpit `flutter analyze` passed. App `flutter analyze` is
  blocked by pre-existing unrelated relay migration errors (`kDefaultRelayUrl`
  references and stale `MeshClient` constructor arguments in relay/mesh tests);
  the app update-info test passed. `flutter` is not on `PATH`; verification
  used the repository SDK at `.tools/flutter/bin/flutter`.
