---
kind: story
release_binding: null
parent: feature-typed-bounded-relay-decoding
stage: done
id: gate-security-extension-inbound-relay-frame-size-caps
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Pi extension decodes inbound relay frames before size caps

## Severity
Low

## Domain
Input Validation & Injection / API Security / Error Handling

## Location
`pi-extension/src/extension/owner_multiplexer.ts:108`

## Evidence
```ts
parsed = JSON.parse(line) as unknown;
...
return decodeClient(Buffer.from(ct, "base64").toString("utf8"));
```

## Issue
Inbound relay envelopes are parsed as full JSON strings and their `ct` payloads are base64-decoded into UTF-8 before the extension applies any explicit raw-frame or decoded-payload size cap. The same shape also appears in `pi-extension/src/transport/peer_channel.ts:101` and `pi-extension/src/extension/command_surface/pairing_coordinator.ts:97`. A compromised relay or paired peer can force avoidable allocation/parse work in the local extension process up to the WebSocket library's default frame limit.

## Remediation direction
Configure an explicit `ws` max payload for the extension client, reject raw relay lines above the protocol cap before `JSON.parse`, reject `ct` values above the encoded/decoded limit before `Buffer.from`, and align the limits with generated protocol `too_large` handling.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical cross-stack boundary work).
- Review weight: `standard` (caller-provided; feature-level review only).
- Files changed: `pi-extension/src/protocol/relay_ingress.ts`, `relay_ingress.test.ts`, `transport/relay_client.ts`, and `relay_client.test.ts`.
- Tests added/updated: injected raw/decoded boundary cases, canonical 32-byte challenge validation, `ws.maxPayload` constructor assertion, and content-free malformed-challenge diagnostics.
- Simplification: auth no longer echoes raw relay challenge/error text; post-auth consumers share one bounded decoder and one rejection vocabulary.
- Discrepancies from design: endpoint constants use the schema's current 4 MiB value and designed derivation, but the existing generator does not project the schema limit metadata into TypeScript and schema/codegen files were outside this worker's allowed write scope.
- Adjacent issues parked: none.
- Verification: TypeScript check passed; 82 focused ingress/relay/owner/cross-PC tests passed.
