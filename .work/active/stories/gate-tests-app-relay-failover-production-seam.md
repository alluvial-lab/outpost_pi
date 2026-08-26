---
id: gate-tests-app-relay-failover-production-seam
kind: story
stage: implementing
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: tests
created: 2026-08-26
updated: 2026-08-26
---

# Exercise configured-to-paired relay failover through the production connection seam

## Priority
High

## Value evidence
Item: `app-relay-url-network-failover`.

Contract / risk / regression: this release addresses the phone dual-homing incident by promising that reconnect tries the configured relay first and the retained pairing-record endpoint second, closing each failed candidate before proceeding (`.work/active/stories/app-relay-url-network-failover.md:16-26`, `app/lib/config/dependencies.dart:280-360`). The only new automated coverage calls `orderedRelayUrls` directly and proves ordering/deduplication (`app/test/data/transport/relay_config_test.dart:97-112`). No test crosses the production loop that creates `WsTransport`, handles a primary timeout/error, drains its child cancellation token, and returns a secure channel from the alternate. A regression that leaves the loop stuck on the first endpoint would therefore preserve all 14 focused tests while recreating the motivating outage.

Focused gate evidence: `flutter test --no-pub test/data/transport/relay_config_test.dart` passed 14/14; inspection confirmed that no other app test references `orderedRelayUrls` or the alternate-failover path. The release's established full-app evidence remains 976/976 and was not rerun.

## Gap type
important-interface / bug-regression / unavailable-dependency failover seam

## Suggested test
```dart
test('primary failure closes its attempt and the paired alternate connects', () async {
  // Drive an injectable production connection seam with two candidate URLs.
  // Make the configured-primary connector fail only after its cancellation
  // boundary is observable; assert that boundary is drained before alternate
  // connect starts, then return the alternate channel and verify its URL.
});

test('parent cancellation during primary attempt never starts the alternate', () async {
  // Cancel the owning token while the first connector is blocked. Assert the
  // first attempt closes and no second candidate or channel is constructed.
});
```

## Test location (suggested)
`app/test/config/production_connection_factory_test.dart` (or a focused transport seam extracted beside `app/lib/config/dependencies.dart`)
