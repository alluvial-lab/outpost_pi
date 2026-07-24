---
id: gate-security-owner-reset-retains-transcripts
kind: story
stage: implementing
tags: [app, security]
parent: feature-owner-identity-transition
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-23
---

# Owner-key replacement leaves the previous owner's transcripts readable

## Severity
Medium

## Domain
Data Protection

## Relevance
Release-relevant

## Location
`app/lib/pairing/storage.dart:294`

## Evidence
```dart
Future<void> wipeAll() async {
  final all = await _store.readAll();
  final prefixes = ['$_kPeersService:', '$_kRoomsService:'];
  for (final key in all.keys) {
```

`OwnerIdentityBridge` invokes this wipe when a different Owner public key is observed (`app/lib/pairing/owner_identity_bridge.dart:149`), but the wipe covers only peer and room secure-storage entries. The app-global transcript key, encrypted `sessions_index_v3`, event boxes, and message projections are neither cleared nor scoped by Owner identity. If the replacement Owner later pairs to the same Pi/session identity, the repositories derive the same box names and can project the prior Owner's cached transcript.

## Remediation direction
Make Owner identity part of the transcript security boundary. On a confirmed Owner-key replacement, either atomically clear the prior Owner's transcript index/projections/events and rotate the transcript key, or namespace both the key and all transcript identities by Owner public-key hash. Add a replacement-owner regression proving old transcript rows cannot be read after the new identity becomes active, while preserving an explicit recovery/data-loss policy.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.

## Remediation chosen (feature-design 2026-07-23)

Operator confirmed Option A: WIPE all transcript-bearing boxes on a confirmed
owner-key replacement (zero residue; same-owner device replacement unaffected;
explicit data-loss policy recorded in the parent feature body). Note:
`wipeAll` already covers channel keys (`_kChannelsService:`) — the gap is
transcripts only. Exact design (facade API, index-derived enumeration +
directory backstop, router hook point, acceptance criteria) is Unit 2 of the
parent feature body.
