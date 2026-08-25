---
id: gate-security-pairing-auth-stall-socket-leak
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: security
created: 2026-08-25
updated: 2026-08-25
---

# Pairing cannot cancel a socket stalled at post-auth readiness

## Severity
Medium

## Domain
API Security

## Location
`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart:115`

## Evidence
```dart
final transport = await _transportFactory(qr, ownerKey);
if (!_isCurrent(generation)) {
  await transport.close();
  return;
}
attempt = _PairingAttempt(transport);
```

## Remediation direction
Give the pairing generation cancellation ownership before awaiting transport creation, pass it into `WsTransport.connect`, and apply an owning timeout that cancels and awaits socket teardown. The v0.8.0 post-auth readiness wait at `app/lib/data/transport/ws_transport.dart:407` must not leave an unowned socket when the pairing ViewModel is disposed, retried, or held indefinitely by a relay that withholds the readiness frame.

## Implementation

- Each pairing generation now owns a cancellation token before transport creation begins; retry, disposal, and timeout cancel the in-flight authenticated-readiness wait.
- The production pairing factory forwards that token to `WsTransport.connect`, whose validated post-auth readiness boundary now remains owned until it returns or is cancelled.
- A 30-second transport-readiness timeout cancels and awaits attempt cleanup before surfacing the existing friendly pairing timeout; stale late transport results are closed rather than adopted.
- Regression coverage holds cancellation cleanup behind an explicit barrier and proves timeout settlement waits for cleanup. Verified with `flutter test test/ui/pairing/pairing_viewmodel_test.dart --concurrency=2` and `flutter analyze`.
