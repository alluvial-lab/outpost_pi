---
id: story-windows-appcast-build-version-contract
kind: story
stage: done
tags: [cockpit, bug, release, windows]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Pair the Windows appcast version with WinSparkle's current-version contract

## Review finding

**Severity:** Blocker

`.github/workflows/cockpit-release.yml:394` now emits the bare pubspec build
number as an item-level `<sparkle:version>`, but the locked Windows updater does
not establish the matching current build number. `cockpit/pubspec.lock:68-75`
pins `auto_updater_windows` 1.0.0; its `AutoUpdater::SetFeedURL` only calls
`win_sparkle_set_appcast_url` and `win_sparkle_init`, not
`win_sparkle_set_app_build_version`. Meanwhile
`cockpit/windows/runner/Runner.rc:64-99` exposes the installed application
version from the Flutter version resources rather than a bare `+n` string.

The locked package's own appcast example also places the Windows
`sparkle:version` on the `<enclosure>` and reserves item-level
`<sparkle:version>`/`<sparkle:shortVersionString>` for macOS. The generated feed
therefore has neither a demonstrated version-domain pairing nor the documented
WinSparkle 0.8.1 element placement. Changing only `${VERSION}` to `${BUILD}` does
not prove that later Windows installs will be offered updates.

## Required outcome

- Choose and implement one tested WinSparkle contract: set the current build
  version through native integration and emit the matching appcast build value,
  or emit the version form/location that the locked plugin compares to the
  installed resource version.
- Preserve the documented one-time manual install across the inherited 1.5.1
  reset.
- Add a deterministic fixture or Windows smoke that proves an installed
  Outpost-Pi build accepts a higher `+n` and rejects an equal/lower one.

## Implementation notes

- Chose the fail-closed dormant-path outcome rather than claiming an untested
  WinSparkle contract. `.github/workflows/cockpit-release.yml` no longer signs
  the Windows installer for an appcast or emits `appcast-windows.xml`; an
  explicitly always-skipped step records the reactivation condition. The
  Windows installer itself is still built and published for manual installs.
- Verified the locked package source in
  `.pub-cache/hosted/pub.dev/auto_updater_windows-1.0.0/`: `SetFeedURL` calls
  only `win_sparkle_set_appcast_url()` and `win_sparkle_init()`. It never calls
  `win_sparkle_set_app_build_version()`. WinSparkle 0.8.1 documents that it
  otherwise reads application metadata from `VERSIONINFO/StringFileInfo`,
  while `cockpit/windows/runner/Runner.rc` supplies the full Flutter
  `x.y.z+n` version string. The package's own Windows example places that
  version on the enclosure, so the removed item-level bare `+n` had neither
  the correct domain nor the demonstrated location.
- Updated `cockpit/packaging/README.md` with the locked-plugin constraint, the
  smoke required before reactivation, and the one-time manual replacement
  from inherited 1.5.1 to the reset 0.x line. No synthetic comparison fixture
  was added because Windows appcast generation is disabled and no update
  acceptance contract is asserted.
- Verification: PyYAML parsed the workflow; a deterministic repository check
  confirmed `appcast-windows.xml` is absent, the always-skipped sentinel and
  inherited-install note are present, and `git diff --check` passes.
- Files changed: `.github/workflows/cockpit-release.yml`,
  `cockpit/packaging/README.md`, and this story.
- Discrepancies from design: used the explicitly permitted disabled-path
  outcome instead of a Windows fixture because the locked plugin exposes no
  paired build-version integration and no honest WinSparkle acceptance smoke
  exists in this repository.
- Adjacent issues parked: none.

## Review (2026-07-15, second pass)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Deep-feature second-pass verification confirmed the sentinel step is unconditionally skipped, the workflow contains no Windows appcast generator/signature variables, and no `appcast-windows.xml` is tracked or uploaded. Windows installers and the macOS/Linux artifact paths remain intact. Story advanced `review -> done`.
