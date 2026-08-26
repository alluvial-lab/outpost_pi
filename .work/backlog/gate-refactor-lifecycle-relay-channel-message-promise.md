---
id: gate-refactor-lifecycle-relay-channel-message-promise
created: 2026-08-26
updated: 2026-08-26
tags: []
release_binding: null
gate_origin: refactor
---

# Relay peer-channel message callbacks discard handler promises

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/relay_transport.ts:722,736`

## Issue
Plain and secure peer-channel adapters invoke `input.onMessage(message)` with `void` even though the callback contract permits a Promise, so asynchronous routing failures are unobserved at the transport boundary.

## Fix
Wrap the callback in an owned rejection-observing dispatch helper and retain the existing channel-generation guard so handler failures are diagnosed without becoming unhandled rejections.
