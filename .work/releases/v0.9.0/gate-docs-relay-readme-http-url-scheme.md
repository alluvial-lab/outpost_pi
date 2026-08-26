---
id: gate-docs-relay-readme-http-url-scheme
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

# Relay README tells users to configure rejected WebSocket URL schemes

## Drift category
readme-staleness

## Location
- Doc: `relay/README.md:88-89`
- Contradicting source: `app/lib/data/transport/relay_config.dart:8-12,68-74,120-130`; `pi-extension/src/config.ts:53-76`

## Current doc text
> Point your app and `pi-extension` to `ws://<your-server-ip>:3000` (or `wss://` if you put it behind a TLS-terminating reverse proxy...)

## Contradiction
The current app and extension user-configured URL boundaries accept canonical `http://` or `https://` only and reject `ws://`/`wss://`. Each transport converts the canonical URL to WebSocket form internally. A user copying the README example receives a validation error rather than a usable configuration.

## Required edit
Document `http://<your-server-ip>:3000` or `https://...` as the value entered in the app and extension. Explain that the clients convert it to `ws://`/`wss://` when opening the socket, while legacy persisted endpoints may be tolerated defensively.

## Closure (2026-08-26)

Updated `relay/README.md` to use canonical `http://`/`https://` values for
client configuration, explain the clients' internal WebSocket conversion, and
correct the reverse-proxy example to `https://`. Verified the app validator at
`app/lib/data/transport/relay_config.dart:109-130` and the extension
validator/conversion at `pi-extension/src/config.ts:69-102`.
