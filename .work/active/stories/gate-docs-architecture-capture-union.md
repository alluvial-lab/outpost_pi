---
id: gate-docs-architecture-capture-union
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Architecture wire-union lists omit the shipped capture-upload family

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:152-166`
- Contradicting source: `protocol/schema/app-pi-client.schema.json:16-18,143-145` and `protocol/schema/app-pi-server.schema.json:26-27,321-322`

## Current doc text
> `ClientMessage` (app → pi) union: ... `thinking_set` / `list_models`.
> `ServerMessage` (pi → app) union: ... `models_list` / `model_select` / `compaction`.
> The generated type registries and decoders derive from the same schema as this union.

## Contradiction
The documented unions are written as complete current wire unions but exclude the
schema-owned capture upload begin/chunk/end and ack/error variants that are now
generated and shipped in the release bundle.

## Required edit
Roll the union descriptions forward to include the capture-upload family and
keep the statement that the generated registries/decoders derive from the same
schema true for every listed variant.
