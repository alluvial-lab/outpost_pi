---
id: gate-refactor-boundaries-lsp-diagnostic-wire-map
kind: story
stage: done
tags: [cockpit]
parent: feature-boundary-typed-decoders
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-08-11
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

## Implementation notes
- Added `LspDiagnosticDecoder` in the LSP data layer to narrow publication, diagnostic, range, and position wire values before constructing typed domain entities.
- Removed JSON constructors/serializers from `LspPosition`, `LspRange`, and `LspDiagnostic`; formatting text edits now reuse the boundary range decoder.
- Preserved empty-batch, scalar fallback, and malformed-range skip behavior, with non-string `source`/`code` normalized to null.
- Verification: `flutter analyze` passed and `flutter test` passed (277 tests).
