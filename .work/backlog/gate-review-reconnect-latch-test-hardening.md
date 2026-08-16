---
id: gate-review-reconnect-latch-test-hardening
created: 2026-08-16
updated: 2026-08-16
tags: [app, testing]
---

# Reconnect regression test must prove the explicit-selection latch (and drop wall-clock sleep)

Important finding from the `feature-upstream-remote-pi-harvest` standard
review (2026-08-16), parked unbound per the review side-effects contract.

`app/test/transport/connection_manager_test.dart:1428-1464` verifies the
room immediately after a same-peer retry but never delivers a subsequent
`RoomsSnapshot` that would clobber the room if the explicit-selection latch
had been reset — so it can pass even if the latch regresses. It also depends
on a 1.1s wall-clock sleep.

## Work

Deterministic retry barrier/fake timer instead of the sleep; deliver a
post-reconnect `RoomsSnapshot` (advertising other rooms) before asserting
the explicitly selected room survives.
