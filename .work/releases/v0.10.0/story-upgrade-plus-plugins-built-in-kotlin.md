---
id: story-upgrade-plus-plugins-built-in-kotlin
kind: story
stage: done
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-28
---

# Upgrade package_info_plus + share_plus to built-in-Kotlin majors

Migrate both plus-family plugins to migrated majors; version/share tests green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Implementation notes

- Execution capability: inline implementation; both plus-family upgrades share
  the same toolchain floor and the app has one version boundary and one share
  boundary to migrate.
- Review weight: standard default; child-story checkpoint review is not
  applicable after green verification.
- Files changed: pub constraints/lock, version adapter and regression, debug-log
  share adapter/regression, and loaded-suite test barriers.
- Tests added: package metadata supplies the running update-check version; the
  debug-log share uses the new `SharePlus.instance.share(ShareParams)` API and
  preserves NDJSON bytes, MIME type, subject/text, and filename override.
- Simplification: dependency setup now consumes the narrow `loadAppVersion`
  adapter, and all debug-log share parameters are assembled at one tested seam.
- Discrepancies from design: package_info_plus 10 and share_plus 13 require
  win32 6, while the unused Windows adapter pulled by flutter_secure_storage 9
  constrains win32 5. Because this app ships only Android/iOS, documented
  overrides move that adapter and its API-compatible platform interface
  together until a deliberate secure-storage major migration removes the
  conflict.
- Adjacent issues parked: none.

## Closure evidence

- `package_info_plus`: 9.0.1 → 10.2.1.
- `share_plus`: 10.1.4 → 13.3.0; deprecated `Share.shareXFiles` removed.
- `flutter analyze`: no issues.
- Targeted version/share tests: 7 passed across their test files.
- Full app suite (`--exclude-tags e2e --concurrency=2`): 987 passed.
- A clean debug APK compiles with the upgraded plus plugins.
