---
kind: story
release_binding: null
parent: feature-piext-lifecycle-delivery-promise-policy
stage: done
id: gate-refactor-lifecycle-queued-delivery-promise
created: 2026-07-12
updated: 2026-07-18
tags: [pi-extension]
depends_on: []
gate_origin: refactor
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

## Consolidated from
`gate-refactor-lifecycle-queued-delivery-fire-and-forget` (duplicate,
archived 2026-07-15). That item captured the same `maybeDrainQueuedMessage`
void-`deliver(...)` gap at `sdk_session_projection.ts:502` (this item
cites `:747` — the function moved between captures); folded here. It had
leaked into backlog as a malformed `stage: drafting` item.

## Implementation

Added an explicit queued-delivery rejection observer. `maybeDrainQueuedMessage`
now invokes delivery synchronously, observes promise rejection through the
caller-supplied callback, and preserves queue clearing and synchronous-throw
behavior. The production adapter logs the queued message id and error without
sending a protocol failure or restoring the queue. Added regression coverage
for asynchronous rejection and synchronous throws.

Verification: `./node_modules/.bin/tsc --noEmit` and
`./node_modules/.bin/vitest run src/session/sdk_session_projection.test.ts`.
