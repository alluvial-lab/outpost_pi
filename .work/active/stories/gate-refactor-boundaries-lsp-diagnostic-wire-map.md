---
id: gate-refactor-boundaries-lsp-diagnostic-wire-map
kind: story
stage: drafting
tags: [cockpit, refactor]
parent: feature-boundary-typed-decoders
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-28
---

# Decode LSP diagnostic maps at the adapter boundary

## Library
boundaries

## Rule
ambiguous-map-to-domain

## Confidence
Medium

## Location
`cockpit/lib/app/core/domain/entities/lsp_diagnostic.dart:14,29,80`

## Issue
The domain entities accept and navigate raw `Map<String, dynamic>` LSP payloads, so the data adapter passes ambiguous wire maps into domain parsing instead of constructing typed domain values at the boundary.

## Fix
Needs analysis: move LSP JSON narrowing into the data-layer LSP decoder/adapter and construct `LspPosition`, `LspRange`, and `LspDiagnostic` through typed constructors, preserving the current fallback policy deliberately.

## Relevance
Release-relevant, but non-blocking under the configured medium-confidence routing. The file is in the `v0.2.0` bundle.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent, so this finding has reduced review isolation.
