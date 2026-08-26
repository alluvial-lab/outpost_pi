---
id: gate-refactor-lifecycle-file-viewer-toolbar-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# File-viewer toolbar actions discard save and format promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:476,481`

## Issue
The toolbar's `VoidCallback` closures invoke asynchronous `_save()` and `_format()` operations without an owned rejection boundary, so failures are detached from the user action.

## Fix
Adapt the toolbar callbacks through `ownAsync` (or an equivalent error-reporting action adapter), preserving the post-action focus restoration and mounted guards inside the async methods.
