---
id: feature-owner-message-e2e-authentication
kind: feature
stage: drafting
tags: [security, app, pi-extension, relay, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-23
---

# End-to-end authentication for relay-routed owner messages

## Brief

The app↔Pi owner data plane wraps JSON as base64 only. Once an owner is
paired, the Pi accepts messages routed with that owner's `peer` id and
dispatches control actions such as `user_message`, `cancel`, `session_new`,
`model_set`, and `thinking_set`. A compromised or malicious relay can
read/alter plaintext frames or inject a forged `ct` under a known owner peer
id, because the Pi verifies relay routing but not end-to-end message
integrity from the owner key.

Add end-to-end integrity for owner data-plane frames: derive a
per-pairing/session key or sign canonical inner messages with
domain-separated context, verify before dispatch, and reject
unsigned/failed frames. Prefer restoring an authenticated encrypted channel
if transcript/tool data should remain hidden from the relay.

## Strategic decisions

- **Fix vs accepted-risk**: **fix** — operator-confirmed 2026-07-23. Build the
  E2E-authenticated owner channel as a paired wire change targeting v0.3.0.
  The fix must be version-paired across app + extension (and relay if
  envelope shape changes), documented in AGENTS.md "Paired wire changes" and
  shipped with a hard-cutover deploy plan like the 0.1.0 rebrand pairs.

## Severity
High (gate-security finding, 2026-07-01; confirmed still live in the
2026-07-23 advisor review)

## Domain
Authentication & Authorization / Cryptography / Data Protection

## Location
`pi-extension/src/transport/peer_channel.ts:72`

## Evidence
```ts
const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
const outer: OuterEnvelope = {
  peer: this.remotePeerId,
  room: APP_DESTINATION_ROOM,
  ct,
};
```

Additional ingress evidence: `pi-extension/src/extension/owner_multiplexer.ts:244`
trusts `outer.peer` for known-owner reattachment, and
`pi-extension/src/transport/peer_channel.ts:111` decodes `outer.ct` without a
message signature or MAC.

## Simplification opportunity

The pairing flow already establishes an ephemeral app key per session; the
design pass should check whether that channel can be extended into the
steady-state data plane rather than introducing a second key-agreement path.
PROTOCOL.md's "relay can see the current envelope contents" assertion rolls
forward in place if encryption lands.

## Origin

Promoted from `.work/backlog/gate-security-relay-owner-messages-unsigned.md`
per advisor review 2026-07-23, recommendation #3.
