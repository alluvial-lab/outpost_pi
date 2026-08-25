---
id: story-harvest-cockpit-crash-class-ports
kind: story
stage: done
tags: [cockpit, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-16
---

# Cockpit crash-class ports: deleted-workspace recovery + bounded Hive-open retry

Cockpit is in daily use (posture change 2026-08-15) — crash-class fixes are
first-class, not public-artifact hygiene.

## 1. Deleted workspace directory must not hang the app — upstream `1a409b40`

A persisted workspace whose directory was deleted leaves the app loading
forever: ours passes the missing path straight to the PTY
(`cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway.dart:20-23`),
`CockpitViewModel.init` only sets ready after activation
(`cockpit_viewmodel.dart:586-588`), and `CockpitPage` fires it
fire-and-forget (`cockpit_page.dart:49`). Upstream resolves a usable spawn
directory (their `spawn_directory.dart:34`) and guarantees `_ready` on every
exit path (their `cockpit_viewmodel.dart:1630`). Port both: fallback spawn
directory + ready-on-failure, with a surfaced error state (not a silent
fallback to $HOME — tell the user the workspace is missing).

## 2. Bounded Hive-open retry at boot — upstream `f923d799` (Hive-lock half)

Ours opens boxes directly at `cockpit/lib/main.dart:42-51`; a transient lock
(dirty shutdown, AV scan on Windows) crashes straight to the OS. Upstream
retries bounded at their `bootstrapper.dart:181`. Port the bounded
open-with-retry + an error screen if boxes never open (do NOT port their
crash-report dialog — we have no report backend). Their dialog-context half
is inapplicable (no such dialog here).

## Verification

`flutter analyze && flutter test`; tests: missing workspace dir → error
state + app ready; Hive open failing N times → bounded retry then error
screen, never an unhandled throw. Cite upstream shas in the commit message.

## Implementation

- Ported deleted-workspace recovery from `1a409b40`: PTY spawns resolve to the
  nearest existing ancestor/home, while the terminal and Cockpit ViewModel
  expose the missing workspace as an error instead of silently hiding the
  fallback. ViewModel initialization now always converges to ready and the
  shell displays a recovery banner.
- Ported only the bounded Hive-lock retry half of `f923d799`: all startup and
  cockpit-module box opens retry transient `FileSystemException`s ten times,
  then the bootstrap catches the final error and renders a standalone startup
  error screen. The upstream crash-report dialog was not ported.
- Added `test/domain/crash_recovery_test.dart` plus a ViewModel restoration
  regression covering missing workspace error state and ready convergence.
- Verification: `cd cockpit && flutter analyze && flutter test` passed (285
  tests).
- Deviation: Flutter tooling rewrote local generated plugin registrants to
  remove unavailable `volume_controller` entries. Those generated files remain
  uncommitted and are intentionally excluded from this story commit.
