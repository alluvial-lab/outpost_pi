---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-cruft-dynamic-setactiveroom-fallback
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-17
---

# Silent dynamic transport fallback for setActiveRoom

## Severity
Low

## Location
app/lib/data/transport/connection_manager.dart:272

## Issue
_propagateActiveRoom uses dynamic to call setActiveRoom and swallows all errors in a blanket catch. A transport/API mismatch can be hidden, silently falling back to implicit default room behavior.

## Recommendation
Add setActiveRoom to the transport contract (or a tiny capability interface), catch only expected unsupported cases, and log unexpected failures so regressions are observable.

## Implementation

Added the typed optional `IActiveRoomTarget` capability across room-aware
channels and pairing transports. Unsupported in-memory transports remain a
no-op without dynamic dispatch. Verified with the focused connection/pairing
tests and `flutter analyze lib test`.
