---
id: feature-boundary-typed-decoders
kind: feature
stage: drafting
tags: [relay, cockpit, pi-extension, refactor]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-28
updated: 2026-07-28
---

# Boundary typed-decoder convergence

## Brief
Three `gate-refactor` findings (scan library `boundaries`, rules
`ad-hoc-wire-parse`, `ambiguous-map-to-domain`, `domains-imports-infra`)
identify untrusted/config wire data parsed into ad-hoc maps or raw JSON values
deep in business logic instead of entering through a typed boundary DTO. Per
`.agents/rules/code-design.md` (Ports and Adapters + Fail fast at boundaries),
untrusted wire data must be decoded at the adapter boundary, not navigated as
ambiguous maps in domain code.

- `gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward` —
  `relay/src/handlers/pi_forward.rs:97` `MeshAuthCache::members_of`
  deserializes a verified mesh envelope into `serde_json::Value` and navigates
  `members`/`remote_epk` with `.get()`; no generated DTO covers this inner
  blob. (Consolidated from the duplicate `mesh-blob-adhoc-parse` finding.)
- `gate-refactor-boundaries-lsp-diagnostic-wire-map` —
  `cockpit/lib/app/core/domain/entities/lsp_diagnostic.dart:14,29,80` domain
  entities accept and navigate raw `Map<String, dynamic>` LSP payloads; the
  data adapter passes ambiguous wire maps into domain parsing instead of
  constructing typed domain values at the boundary.
- `gate-refactor-boundaries-protocol-env-read` —
  `relay/src/protocol/outer.rs:34` the authored protocol parser reads
  `std::env::var(MAX_CT_ENV)` directly, coupling protocol parsing to process
  configuration instead of receiving a parsed limit from the relay
  composition/config boundary.

## Simplification opportunity
Three independent boundary-decoder fixes that each remove an ad-hoc parse/ env
read from domain or protocol code. No shared DTO across the three (different
components), but they share the boundary-typing principle and are worth one
coherent design pass to keep the fix approach consistent.

## Design notes
Scan library `scan-boundaries` declares `findings-route: none` (fixes change
where parsing happens, not black-box-preserving), so this routes through
`feature-design`. The design pass should: (1) design an authored/generated
mesh-members DTO at the mesh-storage boundary for the relay item; (2) move LSP
JSON narrowing into the cockpit data-layer decoder with typed constructors;
(3) move env parsing to the relay config/composition boundary and inject the
max-ct limit into the protocol parser. Each is independently verifiable.
