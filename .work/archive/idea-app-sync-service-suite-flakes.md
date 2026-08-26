---
id: idea-app-sync-service-suite-flakes
created: 2026-08-22
updated: 2026-08-26
tags: [app, testing]
status: duplicate
duplicate_of: gate-security-combined-app-verification-flaky (active) — same test-isolation investigation; evidence folded there; groom 2026-08-26
---

# Stabilize sync-service assertions under the full Flutter suite

During reconnect-churn verification, two consecutive
`flutter test --exclude-tags e2e --concurrency=2` runs failed different
`app/test/data/sync/sync_service_test.dart` assertions while the complete file
passed immediately with `--concurrency=1` (96/96). The first full run failed
session-index assertions in `two session ids on the same room use different
boxes and index keys` and `foreign session_history is dropped before rows or
index mutate`; the second failed `server error clears pending chunk flush so
chat does not stay working` because the awaited runtime projection was still
null. This points to load-sensitive async/test isolation rather than one stable
product failure. Preserve the behavioral assertions; replace elapsed-time
settling with explicit completion barriers or otherwise isolate shared Hive
state without weakening coverage.

## Folded-in (groom 2026-08-25, from backlog-app-sync-test-isolation-flake)
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
