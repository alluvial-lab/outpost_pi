---
id: feature-outpost-pi-distribution-ownership-cockpit-identifiers
kind: story
stage: done
tags: [rebrand, cockpit, release]
parent: feature-outpost-pi-distribution-ownership
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Replace Cockpit platform application identifiers with owned values

Implements Unit 1 of `feature-outpost-pi-distribution-ownership`.

## Scope

Replace `work.jacobmoura.cockpit` → `dev.kevoun.outpostpi.cockpit` across all platform identifiers:

- `cockpit/macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_COPYRIGHT` → dual copyright line)
- `cockpit/macos/Runner.xcodeproj/project.pbxproj` (three `PRODUCT_BUNDLE_IDENTIFIER` entries)
- `cockpit/linux/CMakeLists.txt` (`APPLICATION_ID` + the comment)
- `cockpit/linux/cockpit.desktop` (`Icon`, `StartupWMClass`)
- `cockpit/linux/work.jacobmoura.cockpit.metainfo.xml` → `git mv` to `dev.kevoun.outpostpi.cockpit.metainfo.xml`; update `<id>`, `<developer id>`, `<name>`, `<launchable>`
- `cockpit/linux/runner/my_application.cc` (comment)
- `cockpit/linux/packaging/deb/make_config.yaml` (`startup_wm_class`, `metainfo`)
- `cockpit/linux/packaging/rpm/make_config.yaml` (`metainfo`)
- `cockpit/windows/packaging/exe/make_config.yaml` (`app_id`)
- `cockpit/windows/runner/Runner.rc` (`CompanyName`, `LegalCopyright` → dual copyright line)
- `cockpit/packaging/README.md` (app ID table, metainfo filename, signing identity references → point to the CI-signing story for the parameterized identity)

## Preserve

- `cockpit/CHANGELOG.md` historical release-identity record.
- Genuine `jacobaraujo7/*` dependency URLs in `pubspec.yaml`/`pubspec.lock`.

## Verification

```bash
cd cockpit
export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache
/home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline
/home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze
/home/agent/projects/remote_pi/.tools/flutter/bin/flutter test
```

`rg 'work.jacobmoura.cockpit|jacobmoura' cockpit/` returns only dependency URLs and historical CHANGELOG. `rg 'Jacob Moura' cockpit/` returns only the dual-copyright line and historical CHANGELOG.

## Implementation notes

- Replaced Cockpit's macOS, Linux, and Windows application identifiers with
  `dev.kevoun.outpostpi.cockpit`, including the three macOS test-target bundle
  identifiers.
- Renamed the Linux AppStream metadata file to
  `linux/dev.kevoun.outpostpi.cockpit.metainfo.xml` and updated its AppStream,
  desktop-entry, developer, and package-config references.
- Updated platform copyright/company metadata and the packaging runbook. The
  runbook now uses `APPLE_SIGNING_IDENTITY` rather than naming a particular
  signing identity.
- Verification passed: `flutter pub get --offline`, `flutter analyze`, and
  `flutter test`.

### Discrepancy

`cockpit/distribute_options.yaml` retains the existing literal signing identity.
It is outside this story's exact file scope; the CI-signing story owns its
workflow/configuration migration. Consequently, a raw `rg 'Jacob Moura'
 cockpit/` also reports that configuration line until the CI-signing work lands.

## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).
