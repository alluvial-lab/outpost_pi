---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-cruft-empty-catch-old-channel-close
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-17
---

# Empty catch around old channel close during adopt

## Severity
Low

## Location
app/lib/data/transport/connection_manager.dart:431

## Issue
In adopt, exceptions from old.close() are fully swallowed (catch {}), so close failures are hidden and cannot be diagnosed even if resource teardown is incomplete.

## Recommendation
At minimum log/track close failures while keeping best-effort cleanup; avoid fully silent swallowing.

## Implementation

Normalized replacement/disposal close through one non-blocking owner-local
helper and removed the redundant scheduled `Future`; the Unit 4 connection
persistence story adds the typed lifecycle diagnostic. Focused connection tests
prove close failure cannot abort channel adoption.
