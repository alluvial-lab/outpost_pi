---
id: gate-refactor-lifecycle-owner-multiplexer-detach-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# Synchronous owner teardown helpers discard detach promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/owner_multiplexer.ts:526,531,582`

## Issue
`disconnectOwner`, `revokeOwner`, and `detachAll` invoke the async `detach` operation without awaiting it or attaching a rejection observer, so channel-drain failures can become unhandled promises while teardown proceeds.

## Fix
Route these synchronous teardown entry points through one owned detached-operation helper that observes rejection (or expose an async aggregate for callers that can await it) while preserving the existing channel-set mutation semantics.
