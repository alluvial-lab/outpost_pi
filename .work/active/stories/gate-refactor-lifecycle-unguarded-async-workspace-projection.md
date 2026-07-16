---
kind: story
release_binding: null
parent: feature-cockpit-async-action-ownership
stage: drafting
id: gate-refactor-lifecycle-unguarded-async-workspace-projection
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Async tab disposal is discarded by workspace teardown

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:268,361

## Issue
WorkspaceProjection calls PaneItem.dispose() synchronously even though AgentSession.dispose() is async and owns process/subscription teardown.

## Fix
Needs analysis: add an explicit awaited close/shutdown path for PaneItem resources, or make async teardown intentionally unawaited with error handling.
