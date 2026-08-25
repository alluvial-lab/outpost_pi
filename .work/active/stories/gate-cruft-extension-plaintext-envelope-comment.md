---
id: gate-cruft-extension-plaintext-envelope-comment
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove the stale plaintext-envelope claim from extension integration tests

## Confidence
High

## Category
Stale comment

## Relevance
Release-relevant: the extension integration test surface changed in the durable-transcript delta and still carries the retired pre-owner-channel description.

## Location
`pi-extension/src/extension.test.ts:1-6`

## Evidence
```ts
/**
 * Integration tests: extension default export + pair_request flow + reconnect.
 *
 * Post plan 06: no Noise XX. Pairing is `pair_request → pair_ok|pair_error`
 * over an opaque outer envelope whose `ct` is base64(JSON.stringify(inner)).
 */
```

The test imports and exercises `sealSecureFrame`/the owner-channel keys, and current protocol documentation defines `ct` as a versioned sealed frame rather than base64-encoded plaintext JSON.

## Removal rationale
Rewrite the header to describe the current pair flow and sealed owner-channel frame boundary. Remove the plan-era plaintext/no-Noise archaeology so the test entry point cannot teach agents the retired protocol.

## Risk
None to behavior. Test fixtures may continue to construct explicit plaintext compatibility inputs where their individual cases require them; only the contradictory header prose is removed.
