---
id: gate-docs-multi-device-same-owner-overstated
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Foundation docs overstate same-Owner multi-device coexistence after per-pairing keys

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/DECISIONS.md:80; PROTOCOL.md:402-405`
- Contradicting source: `pi-extension/src/extension/owner_multiplexer.ts:485-503; pi-extension/src/pairing/storage.ts:403-407`

## Current doc text
> Multiple devices with the same Owner-key can coexist connected and receive the same message; supporting multiple devices for one Owner.

## Contradiction
Secure channels and persisted channel material are keyed only by the Owner public key. Attaching or re-pairing that same key replaces the existing channel and peer record; the implementation does not preserve simultaneous independently keyed same-Owner devices.

## Required edit
Roll both assertions forward to the actual one-active-channel-generation-per-Owner-key behavior, including that same-key re-pair replaces the prior generation.

## Implementation notes

Updated `docs/DECISIONS.md` and `PROTOCOL.md` to state one active secure channel generation per Owner key, with same-key attach/re-pair replacing the prior channel and peer record; corrected the protocol overview diagram to match. Verified against `owner_multiplexer.ts` replacement attach flow and `storage.ts` Owner-key replacement.
