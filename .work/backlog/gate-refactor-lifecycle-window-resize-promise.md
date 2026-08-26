---
id: gate-refactor-lifecycle-window-resize-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# Window resize timer runs an unowned async callback

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`cockpit/lib/main.dart:239`

## Issue
The resize debounce passes an `async` closure directly to `Timer`, discarding the futures from `getSize()` and `StateStore.putAll()` and allowing a post-dispose write or unobserved failure.

## Fix
Use an owned detached callback that observes errors and checks the window-state lifecycle before persisting, while retaining debounce cancellation and exit-time flushing.
