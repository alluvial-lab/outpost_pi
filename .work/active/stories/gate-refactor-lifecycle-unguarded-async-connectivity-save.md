---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-connectivity-save
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Relay save action discards its async save future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart:284,296

## Issue
_save() is async but submit/save UI callbacks invoke it without explicit future handling.

## Fix
Needs analysis: wrap with unawaited(_save()) plus internal error handling, or route through an awaited command helper.

## Implementation

Added the shared `ownAsync` / `ownedAsyncAction` core UI boundary and zone-forwarding regression coverage. Connectivity lifecycle loads, relay save/check callbacks, pairing/revoke launches, and the shared reload control now explicitly own their detached futures without changing existing error presentation or mounted-guard behavior.

Verification: `flutter test test/ui/async_action_test.dart test/settings/connectivity_settings_panel_test.dart` passed.
