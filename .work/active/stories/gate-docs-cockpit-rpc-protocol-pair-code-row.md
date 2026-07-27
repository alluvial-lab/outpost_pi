---
id: gate-docs-cockpit-rpc-protocol-pair-code-row
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: docs
created: 2026-07-27
updated: 2026-07-27
---

# Cockpit RPC protocol docs still map the removed pair-code event

## Location
`cockpit/docs/rpc-protocol.md:167`; `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart:152`

## Contradiction
The protocol table claims `outpost-pi:pair-code` maps to `RpcPairCode`, but
that event/entity was removed (producer-less variant dropped repo-wide;
Cockpit reads QR data from the file seam). `RpcNotice` dartdoc also says
notices can carry "QR ready", while the extension's regression asserts no
QR-ready message exists.

## Required edit
Remove the obsolete table row; update the `RpcNotice` dartdoc to describe
only current notice behavior.

## Implementation notes
- Removed the obsolete `outpost-pi:pair-code`/`RpcPairCode` protocol-map row.
- Narrowed `RpcNotice` documentation to current extension status and error notices.
- Verification: confirmed no `RpcPairCode` or QR-ready notice assertion remains in the edited protocol documentation/entity surface.
