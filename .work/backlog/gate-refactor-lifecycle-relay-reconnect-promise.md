---
id: gate-refactor-lifecycle-relay-reconnect-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# Relay reconnect timer discards the reconnect promise

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/relay_transport.ts:492`

## Issue
The reconnect timer calls `void attemptReconnect()` without observing a rejection, so an exception outside its local connection-attempt catch can escape the timer boundary and stop the reconnect loop without diagnosis.

## Fix
Attach a rejection handler at the timer boundary (and preserve scheduling for recoverable failures), or route the callback through a transport-owned detached-operation observer.
