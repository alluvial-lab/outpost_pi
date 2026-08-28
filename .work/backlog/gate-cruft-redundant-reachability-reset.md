---
id: gate-cruft-redundant-reachability-reset
gate_origin: cruft
created: 2026-08-28
updated: 2026-08-28
tags: [cleanup, app]
---

# Remove the redundant ReachabilityAdapter reset path

## Confidence
Medium

## Category
redundant reset / dead helper

## Location
`app/lib/data/transport/connection_manager.dart:676-678` and
`app/lib/data/transport/reachability_adapter.dart:107-129`

## Evidence
```dart
_reachability.onStopRequested();
if (emitNoPeer) {
  _reachability.reset();
```

`ReachabilityAdapter.reset()` assigns the same complete offline/default state as
`onStopRequested()`. Repository search finds no other caller of `reset()`, and
this call immediately follows `onStopRequested()` on the same teardown path.

## Removal
Delete the redundant `_reachability.reset()` call and remove the now-unused
`ReachabilityAdapter.reset()` method. Keep `onStopRequested()` and the existing
`emitNoPeer` state transition; teardown still resets all reachability fields.
