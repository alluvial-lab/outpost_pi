---
id: gate-refactor-protocol-contract-owner-multiplexer-handwritten-types
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# Pairing multiplexer handwrites generated app/Pi message types

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/extension/owner_multiplexer.ts:360`

## Issue
The pairing and detach paths handwrite pair_error, pair_ok, and bye, duplicating values in SERVER_MESSAGE_TYPES.

## Fix
Generate a keyed discriminator registry from the schema and use its pair_error, pair_ok, and bye entries when constructing messages.
