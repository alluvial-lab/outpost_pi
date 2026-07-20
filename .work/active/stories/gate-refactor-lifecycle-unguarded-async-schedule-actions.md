---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-schedule-actions
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Schedule action buttons discard Future-returning callbacks

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/schedule_settings_panel.dart:137,330

## Issue
Future-returning schedule actions are invoked from sync UI callbacks without explicit handling.

## Fix
Needs analysis: use unawaited(...) with callee-side error reporting, or introduce a shared async action runner.

## Implementation

Routed schedule initial reload, periodic refresh, creation, enabled toggle, run, log, and removal actions through the shared owned-async boundary. Existing busy and `actionError` state behavior remains unchanged.

Verification: `flutter test test/settings/schedule_settings_panel_test.dart` and `flutter analyze lib test` passed.
