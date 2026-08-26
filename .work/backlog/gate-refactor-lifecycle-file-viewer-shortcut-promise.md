---
id: gate-refactor-lifecycle-file-viewer-shortcut-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# File-viewer keyboard shortcuts discard async action promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:493,495,501,507`

## Issue
The Cmd/Ctrl-S and Cmd/Ctrl-Shift-F shortcut callbacks return `_save()` or `_format()` through a `VoidCallback` slot without observing their asynchronous failures.

## Fix
Wrap each shortcut action with the cockpit owned-async boundary (including the focus-restoration behavior where required) so keyboard-triggered persistence and formatting cannot create unhandled futures.
