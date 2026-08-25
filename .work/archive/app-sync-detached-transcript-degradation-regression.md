---
status: groom-done
id: app-sync-detached-transcript-degradation-regression
created: 2026-07-24
updated: 2026-07-24
tags: [app, bug]
---

# Detached transcript failure no longer emits its degradation event

**2026-07-24 annotation (orchestrator): NOT REPRODUCED on the integrated
tree.** `flutter test test/data/sync` passed 107/107 repeatedly after all
concurrent workers committed. The observed failure was almost certainly
cross-worker mid-flight contamination (uncommitted changes from another
worker in the shared tree at observation time). Kept as a watch item: if
the degradation-event assertion ever fails on a clean tree, investigate per
below; otherwise delete at next groom.

`cd app && flutter test test/data test/pairing test/ui` fails in
`test/data/sync/sync_service_test.dart` at the test "detached transcript failure
degrades once, requests replay, recovers, and preserves turn convergence".
The expected `SessionPersistenceDegraded` event is absent. This is outside the
pairing worker's write scope (`app/lib/data/sync/**`); reproduce and determine
whether the recent sync lifecycle changes regressed the required degradation
signal.
