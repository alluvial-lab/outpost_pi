---
id: story-windows-appcast-build-version-contract
kind: story
stage: implementing
tags: [cockpit, bug, release, windows]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-14
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
