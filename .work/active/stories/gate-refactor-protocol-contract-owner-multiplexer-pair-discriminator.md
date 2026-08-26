---
id: gate-refactor-protocol-contract-owner-multiplexer-pair-discriminator
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: refactor
created: 2026-08-26
updated: 2026-08-26
---

# Owner multiplexer re-enumerates the generated pair-request discriminator

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/owner_multiplexer.ts:176,309`

## Issue
The pair-request guard compares `message.type` and `inner.type` to the handwritten `"pair_request"` literal even though the generated client-message registry already defines that discriminator.

## Fix
Add or consume a generated named client-message discriminator for `pair_request` and use it for both runtime checks (and derive the related narrowing type from the same generated source).
