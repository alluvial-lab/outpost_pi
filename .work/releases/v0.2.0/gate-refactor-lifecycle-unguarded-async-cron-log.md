---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-cron-log
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Cron log initial load future is discarded

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/dialogs/cron_log_dialog.dart:37

## Issue
initState calls async _load() without await, return, or unawaited.

## Fix
Needs analysis: call unawaited(_load()) and ensure _load handles thrown errors by updating _error/_loading.

## Implementation

The dialog's `initState` now owns its detached log load through `ownAsync`. The existing `null` / `actionError` fallback and mounted guard are unchanged; genuinely uncaught failures still flow to the originating zone.

Verification: `flutter test test/settings/schedule_settings_panel_test.dart` and `flutter analyze lib test` passed.
