---
id: backlog-app-sync-test-isolation-flake
created: 2026-08-16
updated: 2026-08-16
tags: [app, testing, bug]
---

# sync_service_test isolation failure under concurrent suite execution

`app/test/.../sync_service_test.dart` ("server error clears pending chunk
flush...", expected idle event but saw null) fails when the suite runs with
`--concurrency=2` but passes isolated and serialized. Pre-existing (first
documented 2026-08-15 in `story-brand-theme-replacement`); interrupted or
capped verification three times since (brand drain, harvest app waves,
review closure) — workers keep paying rerun/serialized-run tax.

## Cost already materialized

Three drain interruptions in two days; every future app wave pays again.
Load-sensitivity also masks real regressions ("passes alone" is becoming
the reflex answer).

## Work

Find the shared state leaking between concurrent test isolates (likely a
singleton/Hive box/static timer surviving a test, or an event assertion
racing the production 60ms timer — see related
`gate-tests-sync-service-noecho-wallclock-timing` fixed in v0.4.0 for the
timer class). Direction per testing-integrity: explicit barriers/fakes, no
wall-clock waits; goal is green at `--concurrency=2`, not another cap.
