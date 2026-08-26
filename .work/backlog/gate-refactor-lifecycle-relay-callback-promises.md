---
id: gate-refactor-lifecycle-relay-callback-promises
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# Relay transport drops post-connect callback promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/relay_transport.ts:540,542,605,607`

## Issue
Both successful-start paths invoke the optional async `onConnected` and `attachCrossPcBridge` operations with `void` but no rejection observer, allowing callback or attachment failures to become unhandled promises after transport startup.

## Fix
Observe both detached operations at the transport boundary with explicit error handling and generation checks; do not let a callback rejection bypass relay state publication or future reconnect ownership.
