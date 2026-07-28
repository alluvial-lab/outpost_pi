---
id: feature-boundary-typed-decoders
kind: feature
stage: review
tags: [relay, cockpit, pi-extension]
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

## Design decisions

### Mesh-members blob: authored strict DTO at the mesh-storage boundary

No existing generated schema models the Owner-signed JSON *inside* a mesh
`blob`: `protocol/generated/mesh.rs` only models the enclosing HTTP wire
records, and `MeshHeader` intentionally narrows to signature-verification
fields. Add authored Serde types beside that boundary in
`relay/src/mesh/types.rs`:

```rust
#[derive(Deserialize)]
pub(crate) struct MeshMembersBlob {
    pub(crate) members: Vec<MeshMember>,
}

#[derive(Deserialize)]
pub(crate) struct MeshMember {
    pub(crate) remote_epk: String,
}

pub(crate) fn decode_member_keys(
    blob: &[u8],
) -> Result<HashSet<String>, MeshMembersDecodeError>;
```

`decode_member_keys` deserializes the signed bytes after `verify_envelope()`
has authenticated them; it is the sole byte-to-member-identity adapter.
`MeshAuthCache::scan_membership` receives only its `HashSet<String>` result and
never navigates JSON. The decode is deliberately strict for the authorization
projection: an absent/non-array `members`, a non-object member, or a missing or
non-string `remote_epk` rejects the entire blob rather than silently dropping
that member. The scan logs a content-free decode failure and treats that record
as ineligible, therefore it cannot authorize either a partial or malformed
membership. Unknown top-level/member fields remain Serde-ignored to preserve
forward-compatible signed blobs.

### LSP diagnostics: data decoder creates domain values

`LspClientImpl._handleNotification` in
`cockpit/lib/app/core/data/lsp/lsp_client_impl.dart` is the existing LSP data
adapter. Add `cockpit/lib/app/core/data/lsp/lsp_diagnostic_decoder.dart` with a
package-private/public-as-needed `LspDiagnosticDecoder` that accepts only
`Object?` wire values and returns typed domain values:

```dart
class LspDiagnosticDecoder {
  const LspDiagnosticDecoder();

  LspDiagnosticsBatch? decodePublishDiagnostics(Object? params);
  LspDiagnostic? decodeDiagnostic(Object? wire);
}
```

It owns map/list narrowing and constructs `LspPosition(line, character)`,
`LspRange(start, end)`, and `LspDiagnostic(...)` through their typed
constructors. Remove `fromJson` constructors and `toJson` wire methods from
`cockpit/lib/app/core/domain/entities/lsp_diagnostic.dart`; its entities retain
only typed fields, constructors, and `LspSeverity.fromWire` (a typed value
normalizer). `LspClientImpl` delegates its notification payload to the decoder
and emits only a decoded batch.

Preserve the useful existing fallbacks explicitly: missing/non-numeric
position coordinates become zero, unknown/missing severity becomes `error`,
and missing/non-string message becomes an empty trimmed string; absent or
non-string `source`/`code` becomes null. A malformed required `range`,
`start`, or `end` rejects that individual diagnostic at the adapter (and a
non-map diagnostics entry is skipped). A notification with a valid params map
but missing/non-list diagnostics still emits the current empty batch; a
non-map `params` is ignored. Thus no raw `Map<String, dynamic>` enters domain
construction while benign server omissions retain current UI behavior.

### Outer-envelope limit: compose configuration, inject parser

Add a relay composition configuration value (in a new
`relay/src/config.rs`, wired by `relay/src/main.rs`) that reads
`RELAY_MAX_CT_MIB` once, applies the existing trimmed-positive-integer/default
and saturating-MiB policy, and exposes its parsed `max_ct_bytes`. Environment
access and its defaulting policy live only there.

Replace the global `OnceLock` helpers in `relay/src/protocol/outer.rs` with an
injected parser:

```rust
#[derive(Debug, Clone, Copy)]
pub struct OuterEnvelopeParser {
    max_ct_bytes: usize,
}

impl OuterEnvelopeParser {
    pub const fn new(max_ct_bytes: usize) -> Self;
    pub fn max_ct_bytes(&self) -> usize;
    pub fn max_ws_message_bytes(&self) -> usize;
    pub fn parse_line(&self, line: &str) -> Result<OuterEnvelope, ParseError>;
}
```

`main` creates this parser from the parsed config, logs the effective limit,
and puts it in `AppState`. `relay/src/protocol/frame.rs` changes its public
entry point to take `&OuterEnvelopeParser` (or its decoder wrapper) and uses it
for outer parsing; `relay/src/handlers/peer.rs` uses the same instance to set
WebSocket frame/message limits and decode incoming frames. This gives transport
admission and JSON parsing one configured source of truth, while unit tests
construct parsers with explicit limits rather than mutating process state.

## Implementation units and acceptance criteria

1. **`gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward` — relay mesh DTO**
   - Edit `relay/src/mesh/types.rs` (and `mesh/mod.rs` exports if required) to
     own the authored members DTO/decode error; update
     `relay/src/handlers/pi_forward.rs` to consume typed member keys in scan
     and invalidation paths. Keep signature verification and owner-hash checks
     before membership authorization.
   - Add focused relay tests for a well-formed signed blob authorizing both
     siblings; malformed `members` and malformed `remote_epk` rejecting the
     whole record; and invalidation treating a malformed newly-published blob
     as no current member keys without authorizing it.
   - Acceptance: `pi_forward.rs` has no `serde_json::Value`, `.get`,
     `.as_array`, or `filter_map` membership parsing; bad member data cannot
     produce a partially-authorized set.

2. **`gate-refactor-boundaries-lsp-diagnostic-wire-map` — cockpit LSP decoder**
   - Add the data-layer decoder, update `lsp_client_impl.dart`, and simplify
     `lsp_diagnostic.dart` to typed entities. Keep its domain/data dependency
     direction (`data -> domain`) and leave UI consumers on typed diagnostics.
   - Add decoder/client tests for a valid publication flowing as typed values,
     fallback values for optional/scalar fields, and malformed ranges/non-map
     diagnostics being rejected/skipped at the adapter.
   - Acceptance: domain diagnostic constructors accept no map/JSON input and
     `LspClientImpl` never calls a domain `fromJson`; emitted batches contain
     only typed domain objects.

3. **`gate-refactor-boundaries-protocol-env-read` — relay parser configuration**
   - Add the relay config value and inject `OuterEnvelopeParser` through
     `AppState`, frame decoding, and the WebSocket transport configuration;
     remove direct `std::env` and `OnceLock` reads from `protocol/outer.rs`.
   - Add tests for config parsing/default/fallback and explicit parser limits:
     exact boundary acceptance, over-limit rejection, and raw WebSocket limit
     derived from the same configured decoded-payload limit.
   - Acceptance: protocol modules are deterministic from constructor inputs;
     only the config/composition boundary reads `RELAY_MAX_CT_MIB`; runtime
     transport and parser enforce the same limit.

## Risks

- **Malformed mesh membership semantics are security-sensitive.** The DTO must
  fail closed for the full signed record, not retain valid-looking siblings by
  filtering malformed entries. Cache/invalidation behavior must not turn a
  malformed publish into an authorization grant; it may only cause a
  conservative miss/rescan.
- LSP servers vary in optional diagnostic fields. Preserve the stated scalar
  fallbacks while rejecting structural range corruption, so strict boundary
  typing does not turn ordinary incomplete diagnostics into a process failure.
- The outer parser currently has global convenience functions used by both
  WebSocket setup and decode. Thread one injected instance through both paths
  before removing globals so their limits cannot diverge.

## Test approach

Run focused Rust unit tests for mesh decoding, outer/frame parsing, and the
relay suite; run Cockpit decoder/unit tests plus `flutter analyze` and the
relevant `flutter test` scope. Tests assert boundary rejection/skip behavior
and typed values reaching authorization or UI streams, not merely helper
coverage.

## Order

All three stories are independent and may execute in parallel:

1. `gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward`
2. `gate-refactor-boundaries-lsp-diagnostic-wire-map`
3. `gate-refactor-boundaries-protocol-env-read`

Each has `depends_on: []`; no cycle is introduced.

## Open questions

None. The existing generated mesh schema demonstrably covers only the outer
mesh HTTP records, so an authored interior-blob DTO is the appropriate
contract.

## Implementation summary

- Relay mesh authorization now decodes signed member blobs through strict
  authored Serde DTOs, rejecting malformed records as a whole.
- Relay outer-envelope limits now enter through composition config and one
  injected parser shared by WebSocket admission and frame decoding.
- Cockpit LSP notifications now narrow wire data in the data adapter before
  constructing typed domain diagnostics.
