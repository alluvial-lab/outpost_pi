---
id: story-upgrade-app-settings-built-in-kotlin
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

# Upgrade app_settings to its built-in-Kotlin major + settings-link regression

Major migration of app_settings; verify settings-link behavior post-upgrade.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Implementation notes

- Execution capability: inline implementation; one package constraint plus its
  two permission-to-settings UI call sites and regression form one boundary.
- Review weight: standard default; child-story checkpoint review is not
  applicable after green verification.
- Files changed: `pubspec.yaml`/lock, chat permission feedback, shared settings
  snackbar helper, its widget regression, and verification-only lint/barrier
  cleanup exposed while running the mandatory full suite.
- Tests added: one widget regression proves the visible Settings action invokes
  the supplied application-settings launcher. Two existing async SyncService
  tests now wait on their named projection predicates rather than assuming 100
  event-loop turns always outpace loaded Hive I/O.
- Simplification: camera and microphone permission paths share one actionable
  settings-link builder instead of duplicating SnackBar construction.
- Discrepancies from design: none; `AppSettings.openAppSettings` remains the
  current API in 9.0.0, so call-site behavior required no signature adaptation.
- Adjacent issues parked: none.

## Closure evidence

- `app_settings`: 5.2.0 → 9.0.0.
- `flutter analyze`: no issues.
- Targeted settings-link regression: 1 passed.
- Full app suite (`--exclude-tags e2e --concurrency=2`): 985 passed.
