---
id: gate-cruft-unused-pi-host-wait-until-ready
gate_origin: cruft
created: 2026-08-26
updated: 2026-08-26
tags: [app, cleanup, testing]
---

# Remove the unused Pi-host readiness helper

## Confidence
Medium

## Severity
Low

## Relevance
Ambient: this is test-only E2E scaffolding in a release-touched support file,
not a production path.

## Category
unused helper / leftover E2E scaffolding

## Location
`app/test/e2e/support/pi_host_client.dart:86-93`

## Evidence
```dart
Future<PiHostStatus> waitUntilReady() => eventually<PiHostStatus>(
  () async {
    final value = await status();
    return value.relayConnected && value.state == 'started' ? value : null;
  },
  timeout: const Duration(seconds: 45),
  description: 'Pi host relay-ready state',
);
```

Call-site search across the current repository finds no invocation of
`PiHostClient.waitUntilReady()`. The current E2E setup uses
`restartForIsolation()`, `status()`, and `eventually` directly; the only other
match is historical release documentation. `eventually` remains live through
`_restart`, so removing this wrapper does not remove a required import.

## Removal
Delete `waitUntilReady()` from `PiHostClient`. Preserve `status()` and the
restart/pairing readiness checks used by current E2E tests.
