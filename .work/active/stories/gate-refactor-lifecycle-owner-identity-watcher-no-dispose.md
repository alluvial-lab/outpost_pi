---
id: gate-refactor-lifecycle-owner-identity-watcher-no-dispose
kind: story
stage: done
tags: [app]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Owner identity watcher is registered without lifecycle disposal

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `resource-no-dispose`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`app/lib/config/dependencies.dart:96`

## Issue
OwnerIdentityBridge owns a platform stream subscription and implements dispose(), but addInstance provides no disposal hook, so disposeDependencies() does not cancel its watcher.

## Fix
Register the bridge through an injector binding with an onDispose callback, or explicitly call OwnerIdentityBridge.dispose() from disposeDependencies().

## Design checkpoint
Use injector ownership, not a one-off manual disposal list. Extend `app/lib/config/utils/injector.dart`:

```dart
void addInstance<T>(
  T instance, {
  void Function(T value)? onDispose,
});
```

Adapt the callback to `BindConfig<T>(onDispose: onDispose)`, then register `OwnerIdentityBridge` in `app/lib/config/dependencies.dart` with `onDispose: (bridge) => bridge.dispose()`. Registrations without a callback retain existing behavior, and `disposeDependencies()` remains the sole app-lifetime boundary.

## Acceptance evidence
- A fresh `CustomInjector` invokes an owned instance's disposal callback exactly once.
- The production bridge binding supplies `dispose`.
- A platform-store event after bridge disposal cannot invoke transition work or remain subscribed.

Use a focused `app/test/config/custom_injector_test.dart` plus the existing `app/test/pairing/owner_identity_bridge_test.dart`; do not re-bootstrap the committed module-global production injector in tests.

## Implementation notes

- Added optional typed instance disposal to `CustomInjector` and bound the
  production `OwnerIdentityBridge` to `bridge.dispose()` at app teardown.
- Added focused injector exactly-once disposal and bridge watch-cancellation
  regressions.
- Verification: focused injector/bridge tests passed; `flutter analyze`
  passed. The combined suite hit the tracked pre-existing `ToolRequest flush
  is not re-amplified` flake; the affected SyncService suite passes in
  isolation.
