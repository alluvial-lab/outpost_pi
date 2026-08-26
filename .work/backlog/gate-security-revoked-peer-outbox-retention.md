---
id: gate-security-revoked-peer-outbox-retention
kind: story
tags: [app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-26
updated: 2026-08-26
---

# Revoking a peer leaves pending prompts eligible for delivery after re-pairing

## Severity
Medium

## Domain
Data Protection

## Location
`app/lib/ui/settings/viewmodels/settings_viewmodel.dart:102`

## Evidence
```dart
Future<void> revoke(String epk) async {
  // ...
  await _storage.deletePeer(epk);
  final remaining = await _storage.listPeers();
```

Revocation removes the peer and owner-channel keys but does not remove that peer's new durable outbox rows. `HiveOwnerDeliveryOutbox` exposes only upsert, room listing, and confirmation deletion (`app/lib/data/local/hive_owner_delivery_outbox.dart:16-57`); after the same Pi/room is paired again, recovery lists those retained rows and retargets them to the new session (`app/lib/data/sync/sync_service.dart:1125-1150`). A prompt the user believed was abandoned at revocation can therefore cross a newly established trust boundary.

## Remediation direction
Add a peer-scoped purge operation to the outbox contract and make revocation durably remove pending deliveries for that EPK before the channel capability is forgotten. Serialize purge against outbox recovery/re-pair activation, and test revoke followed by same-EPK/same-room re-pair to prove no pre-revocation prompt is sent.
