---
kind: story
release_binding: null
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-workspace-projection
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
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

## Implementation

Added the explicit async `PaneItem.close()` contract and moved agent/terminal resource teardown out of Flutter's synchronous notifier `dispose()`. `WorkspaceProjection` removes tabs and cancels debounce ownership before awaiting watcher cancellation and pane shutdown; project and whole-projection disposal await all selected tabs. Async Cockpit boundaries now await teardown, while synchronous widget/ViewModel boundaries use `ownAsync`.

Regression coverage proves immediate tab removal, delayed agent gateway shutdown completion, project/full projection fan-in, active-turn convergence, and terminal output cancellation before PTY kill.

Verification: `flutter test test/ui/agent_session_turn_projection_test.dart test/ui/workspace_projection_test.dart test/ui/cockpit_viewmodel_workspace_commands_test.dart test/ui/cockpit_viewmodel_workspace_document_test.dart` and `flutter analyze lib test` passed.
