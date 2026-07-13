---
id: gate-refactor-lifecycle-queued-delivery-promise
created: 2026-07-12
updated: 2026-07-12
tags: [pi-extension]
---

# Observe rejected queued-message delivery promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/session/sdk_session_projection.ts:747`

## Issue
`maybeDrainQueuedMessage` explicitly voids `deliver(...)`, whose contract allows `Promise<void>`, without attaching rejection handling; a rejected queued delivery can become an unobserved promise failure.

## Fix
Define the intended queued-delivery failure policy and attach an explicit rejection handler (or return/await through an owned async boundary) while preserving turn-state convergence.
