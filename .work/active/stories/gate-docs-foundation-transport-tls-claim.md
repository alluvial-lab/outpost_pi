---
id: gate-docs-foundation-transport-tls-claim
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: docs
created: 2026-08-26
updated: 2026-08-26
---

# Foundation transport documentation claims relay WebSockets are intrinsically TLS

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/SPEC.md:91-94`; `docs/ARCHITECTURE.md:16`
- Contradicting source: `relay/src/main.rs:76-84`; `PROTOCOL.md:520-525`

## Current doc text
> `WebSocket over TLS (relay-mediated)`
>
> `TLS WS (pi_envelope)` and `TLS WS (ClientMessage/ServerMessage)`

## Contradiction
The relay binds a plain `TcpListener` and serves HTTP/WebSocket directly; TLS is supplied only by an external terminating proxy. The canonical protocol contract explicitly says the reference deployment uses plain `ws` and that transport encryption is deployment-dependent. These foundation claims overstate the protection of both app and cross-PC paths.

## Required edit
Replace the transport labels with deployment-dependent WebSocket/TLS wording: the relay serves plain `ws` by default, while `wss` requires an external TLS-terminating proxy. Keep the owner-channel E2E and cross-PC plaintext distinctions explicit.

## Closure (2026-08-26)

Updated `docs/SPEC.md` and `docs/ARCHITECTURE.md` to state that the relay
serves plain `ws` by default, external TLS termination is required for `wss`,
post-pairing owner payloads remain E2E-protected, and cross-PC bodies remain
relay-readable. Verified the transport implementation at
`relay/src/main.rs:76-84` and the canonical protection contract at
`PROTOCOL.md:528-534`.
