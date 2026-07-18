---
kind: story
release_binding: null
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-daemon-actions
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# Daemon action buttons discard Future-returning callbacks

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart:299,354,486

## Issue
Future-returning daemon actions are invoked from sync button callbacks without explicit unawaited or error handling at the callsite.

## Fix
Needs analysis: use unawaited(...) with callee-side error reporting, or introduce a shared async action runner.

## Implementation

Routed daemon initial reload, periodic refresh, create/fleet/supervisor controls, and per-daemon actions through the shared owned-async boundary. Existing busy and `actionError` projection remains unchanged.

Verification: `flutter test test/settings/daemon_settings_panel_test.dart` and `flutter analyze lib test` passed.
