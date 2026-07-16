---
kind: story
release_binding: null
parent: feature-cockpit-async-action-ownership
stage: drafting
id: gate-refactor-lifecycle-unguarded-async-connectivity-save
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
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
