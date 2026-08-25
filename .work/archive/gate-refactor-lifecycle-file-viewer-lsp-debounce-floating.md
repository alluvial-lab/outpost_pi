---
id: gate-refactor-lifecycle-file-viewer-lsp-debounce-floating
status: superseded
superseded_by: backlog-cockpit-file-watch-reliability (groom merge d4d514e, 2026-07-22)
created: 2026-07-20
updated: 2026-07-24
tags: []
release_binding: null
gate_origin: refactor
---

# Own debounced file-viewer LSP updates

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:240`

## Issue
The edit-debounce timer discards the `Future<void>` returned by `lspChangeDocument(...)`, so an unexpected asynchronous LSP failure is unobserved and can race widget disposal without an explicit ownership policy.

## Fix
Needs analysis: route the timer callback through Cockpit's owned-async boundary (or attach an equivalent rejection observer), while retaining debounce cancellation and preventing post-dispose publication.

## Relevance
Ambient. The callback predates the `cockpit-v0.2.0` bundle; the release only changed this file's formatter-reload diagnostics path.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent; this finding therefore has reduced review isolation.
