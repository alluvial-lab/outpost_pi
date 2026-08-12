---
id: backlog-hot-reload-arm-path-behavioral-tests
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension]
---

# Behavioral tests for hot-reload.sh arm path

## Origin
gate-tests T2 (v0.4.0); deferred.

## Location
scripts/hot-reload.sh:81-134.

## Issue
The documented agent workflow (arm: locate nearest Pi ancestor, validate owner-only runtime identity, verify identity PID/nonce shape, exclusively create .hot-reload-armed-<PID>) has no behavioral test. The only subprocess invocation of hot-reload.sh is the off cleanup test.

## Work
Subprocess harness with controlled ancestry + runtime-identity dir: cover successful nonce propagation, an intermediate shell ancestor, PID mismatch rejection, malformed/missing identity, toggle off, and duplicate O_EXCL arm rejection.
