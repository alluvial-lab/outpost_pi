---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-language-settings
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# LSP probe future is fired without explicit handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/language_settings_panel.dart:112,151,161

## Issue
_detect() is async but is called from sync paths without await/unawaited.

## Fix
Needs analysis: wrap probe calls in unawaited(_detect()) and make _detect catch/report probe errors deterministically.

## Implementation

Initial, saved-command, and reset-command LSP probes now pass through `ownAsync`. The probe still clears availability immediately and publishes only while mounted; no cancellation, retry, or new error state was introduced.

Verification: `flutter test test/settings/app_preferences_settings_panel_test.dart` and `flutter analyze lib test` passed.
