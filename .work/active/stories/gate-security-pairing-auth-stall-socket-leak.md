---
id: gate-security-pairing-auth-stall-socket-leak
kind: story
stage: implementing
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
