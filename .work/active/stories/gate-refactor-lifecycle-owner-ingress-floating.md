---
id: gate-refactor-lifecycle-owner-ingress-floating
kind: story
stage: drafting
tags: [pi-extension]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-28
---

# Observe asynchronous owner-ingress routing failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/index.ts:319`

## Issue
The relay outer-message callback explicitly voids `_handleOwnerOuterFrame(...)` without awaiting, returning, or attaching a rejection handler, so a rejected asynchronous peer lookup can escape as an unhandled promise failure.

## Fix
Return the routing promise through an owned async dispatch boundary or attach an explicit rejection observer that records a payload-free diagnostic while preserving the connection-generation guard.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent; this finding therefore has reduced review isolation.
