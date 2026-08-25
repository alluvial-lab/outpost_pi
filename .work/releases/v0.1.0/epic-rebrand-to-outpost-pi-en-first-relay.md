---
id: epic-rebrand-to-outpost-pi-en-first-relay
kind: feature
stage: done
tags: [rebrand, docs, i18n, relay]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first + rustdoc gap-fill — relay

## Brief

Translate Portuguese → English and adopt the rustdoc documentation framework
in `relay/`. The smallest code slice alongside pi-extension: 1 PT-bearing
source file (`relay/src/protocol/outer.rs`). PT is comment prose; the relay
has no user-facing UI strings.

Covers `relay/src/` only. Gap-fill scope is the Always tier per the doc
convention: `pub` items (functions, structs, enums, traits) get rustdoc `///`
comments with `# Errors` sections where the function returns a `Result`.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent small slice. No `depends_on` — the relay's
  wire-stable identifiers already migrated in the first rebrand epic; this is
  pure comment/doc work. Can run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — rustdoc `///` format
  and the Always tier (`pub` items). The `# Errors` section convention for
  `Result`-returning functions is shown in the skill's Rust example.
- `.agents/skills/rust-relay/SKILL.md` — relay code reference; read before
  editing `relay/`.
- Parent epic `## Grounded surface measurement` — the 1-file count.

## What this feature does NOT cover
- Wire-stable identifiers (auth domain string) — owned by the first rebrand
  epic's wire-stable migration feature, already shipped.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`target/`).

## Verification
```bash
# from relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build
```
Plus a grep confirming zero PT (accented Latin) in `relay/src/`.

## Design decisions

- **Public-item boundary**: audit direct `pub` declarations in handwritten
  `relay/src/` modules, including constants and inherent methods; exclude
  `pub(crate)` implementation details, module/re-export declarations, test-only
  helpers, and `protocol/generated/` output. This matches the convention's
  Rust `pub` API boundary while avoiding generated-contract churn.
- **Translation safety**: translate every Portuguese doc or ordinary code
  comment in `relay/src/protocol/outer.rs`, including its test comments, but do
  not alter literals, serde names, wire fields, error strings, or behavior.
  The outer envelope remains opaque and wire-stable.
- **Rustdoc form**: add concise `///` intent/contract comments only; every
  `Result`-returning public function receives a `# Errors` section naming its
  existing error variants or handler failure mapping. No doctests are needed
  for this comment-only slice.
- **Execution shape**: no child stories. The audit and the edits are one
  cohesive, bounded documentation pass with one Rust verification surface;
  splitting it would add handoff overhead without independent acceptance or
  meaningful implementation parallelism.

## Discovery and audit

- **Dispatch rationale**: direct-read only. This raised-tier worker verified
  the bounded relay source map locally (36 Rust files, one PT-bearing
  handwritten file); no separate exploration adds useful ownership or
  uncertainty reduction.
- `relay/src/protocol/outer.rs` is the only PT-bearing source file. The PT is
  comment prose, including test comments; no relay UI or protocol literal is in
  scope.
- `relay/src/protocol/generated/` contains generated schema projections and is
  Skip-tier even though it has public declarations. It must not be annotated
  by hand.
- The public-item audit below is the implementation checklist. It intentionally
  excludes `#[cfg(test)] FirehoseMetrics::snapshot` and `pub(crate)` items.

### Missing rustdoc checklist

| File | Public items that need `///` rustdoc |
| --- | --- |
| `relay/src/auth/challenge.rs` | `AuthenticatedPeer`, `AuthError`, `parse_hello_bootstrap`, `verify_auth` |
| `relay/src/handlers/control.rs` | `ControlFrameError` |
| `relay/src/handlers/pi_forward.rs` | `MeshAuthCache::new` |
| `relay/src/mesh/handler.rs` | `post_mesh`, `get_mesh` |
| `relay/src/mesh/store.rs` | `StoreError` |
| `relay/src/mesh/verify.rs` | `VerifyError` |
| `relay/src/metrics.rs` | `FirehoseMetrics`, `FirehoseMetrics::new`, `inc_peer_online_emitted`, `inc_peer_online_suppressed`, `inc_presence_emitted`, `inc_presence_suppressed`, `inc_rooms_emitted`, `inc_rooms_suppressed` |
| `relay/src/peers/connections.rs` | `ConnectionRemove` |
| `relay/src/peers/registry.rs` | `PeerRegistry`, `PeerRegistry::new` |
| `relay/src/presence.rs` | `PresenceManager`, `PeerPresence`, `PresenceManager::new` |
| `relay/src/protocol/frame.rs` | `DecodedRelayFrame`, `FrameDecodeError`, `decode_relay_frame` |
| `relay/src/protocol/outer.rs` | `ParseError` |
| `relay/src/reachability.rs` | `ReachabilityState`, `ReachabilityState::as_wire`, `REACHABILITY_STATES`, `REACHABILITY_BACKOFF`, `reachability_backoff`, `RELAY_WS_PING_INTERVAL`, `APP_PROTOCOL_PING_INTERVAL`, `EXTENSION_LIVENESS_CHECK_INTERVAL`, `EXTENSION_LIVENESS_TIMEOUT`, `DEGRADED_AFTER_MISSED_APP_PONGS` |
| `relay/src/rooms.rs` | `RoomManager::new` |

Existing rustdoc remains in place unless its prose is Portuguese in
`protocol/outer.rs`; do not replace useful current EN contract documentation.

## Architectural choice

Use a focused **comment-only, source-owned documentation pass**: translate
`protocol/outer.rs`, then fill the audited handwritten `pub` declarations in
place with rustdoc derived from their existing contracts and tests.

Alternatives rejected:

1. **Translate only `outer.rs`** — smaller diff, but fails the epic's native
   rustdoc gap-fill commitment.
2. **Annotate all syntactically visible declarations, including generated and
   `pub(crate)` code** — broadest coverage, but contradicts the convention's
   public API/Skip-tier boundary and would create generated-code drift.
3. **Add an external documentation registry or wrapper module** — centralizes
   prose but separates contracts from declarations and cannot render as native
   rustdoc where callers need it.

## Implementation units

### Unit 1: Translate the outer-envelope commentary

**File**: `relay/src/protocol/outer.rs`

```rust
pub const MAX_CT_ENV: &str = "RELAY_MAX_CT_MIB";
pub const DEFAULT_MAX_CT_MIB: usize = 4;
pub fn max_ct_bytes() -> usize;
pub enum ParseError {
    InvalidJson(serde_json::Error),
    TooLarge(usize, usize),
}
pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError>;
```

**Implementation notes**:
- Translate the existing `///` contract comments and all test `//` comments to
  EN without changing the above signatures or their strings/values.
- Add EN rustdoc for `ParseError`; retain the existing generated
  `OuterEnvelope` re-export and `to_json_string` adapter as-is.
- Expand `parse_line`'s rustdoc with `# Errors` for malformed JSON and the
  configured ciphertext-size limit.

**Acceptance criteria**:
- [ ] No Portuguese comment prose remains in `outer.rs`, including tests.
- [ ] `ParseError` and `parse_line` have EN rustdoc; the latter documents both
  `InvalidJson` and `TooLarge` under `# Errors`.
- [ ] No wire literal, error value, size calculation, or test assertion changes.

### Unit 2: Fill handwritten public Rust API rustdoc

**Files**: the fourteen handwritten source files in the audit table above.

```rust
/// <intent and non-obvious contract>
pub struct /* or enum / const / function */;

/// <operation and boundary contract>
///
/// # Errors
///
/// <existing failure variants and conditions>
pub fn /* Result-returning public function */(...) -> Result<..., ...>;
```

**Implementation notes**:
- Use the audit table as the single implementation checklist; re-run the
  declaration scan before committing so new/removed declarations cannot make
  the checklist stale.
- Keep docs about behavior, opacity, lifecycle, bounds, and error mapping —
  not redundant field/type descriptions. In particular, `decode_relay_frame`,
  auth parsing/verification, and mesh HTTP handlers must document their
  fail-fast boundaries without claiming E2E or inspecting payload bodies.
- Add `# Errors` sections to newly documented Result-returning functions:
  `parse_hello_bootstrap`, `verify_auth`, `post_mesh`, `get_mesh`, and
  `decode_relay_frame`. Existing Result docs elsewhere are reviewed for the
  same convention during the pass.
- Do not hand-edit `relay/src/protocol/generated/`; schema-generated types,
  generated module declarations, and test-only helpers remain Skip tier.

**Acceptance criteria**:
- [ ] Every audited handwritten direct `pub` item has concise EN `///` rustdoc.
- [ ] Every audited public `Result` function has a truthful `# Errors` section.
- [ ] Generated files, `pub(crate)` details, module/re-export lines, and tests
  receive no gap-fill-only documentation churn.

## Implementation order

1. Translate and document `relay/src/protocol/outer.rs`, preserving its
   opaque-envelope boundary and tests.
2. Apply the audit-table rustdoc additions, prioritizing parse/auth/frame/mesh
   boundaries and then state, metrics, and reachability APIs.
3. Re-run the public-item audit and PT grep; review every `# Errors` section
   against the existing implementation.
4. Run the relay formatter, lint, tests, build, and rustdoc smoke check.

## Testing and verification

No new behavior tests are warranted: the change changes comments only and the
existing unit/integration tests already specify the contracts being documented.
Verification is evidence that the documentation pass did not alter behavior or
leave audit gaps:

```bash
# From relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build
cargo doc --no-deps

# From repository root: no accented Portuguese remains in relay source.
grep -RInE '[ÁÀÃÂÉÊÍÓÔÕÚÜÇáàãâéêíóôõúüç]' relay/src
```

The implementation pass will use a non-committed declaration scan to assert
that each handwritten direct `pub` declaration (excluding generated and
`#[cfg(test)]` items) has immediately preceding `///` rustdoc, then manually
check `# Errors` coverage for Result-returning functions. The PT grep must
return no matches; generated files are not edited regardless of that scan.

## Risks

- **Scope drift from Rust visibility nuances**: generated and `pub(crate)`
  declarations could be mistaken for public API. Mitigation: the audit table
  and direct-`pub` rule are explicit; re-run the scan before commit.
- **Comment translation can accidentally change a protocol claim**: mitigate
  by preserving literals and reviewing against the existing outer-envelope
  implementation and relay opacity rules rather than translating by blind
  replacement.
- **Incomplete error contracts**: mitigate by reviewing every newly documented
  Result function's actual error paths and running `cargo doc --no-deps` after
  formatting.

## Other agent review

- Skipped: this is a bounded comment/rustdoc-only design with no architectural
  or wire decision; the parent epic and documentation convention already lock
  the relevant choices.

## Implementation notes

- Files changed: `relay/src/auth/challenge.rs`, `relay/src/handlers/control.rs`,
  `relay/src/handlers/pi_forward.rs`, `relay/src/mesh/handler.rs`,
  `relay/src/mesh/store.rs`, `relay/src/mesh/verify.rs`, `relay/src/metrics.rs`,
  `relay/src/peers/connections.rs`, `relay/src/peers/registry.rs`,
  `relay/src/presence.rs`, `relay/src/protocol/frame.rs`,
  `relay/src/protocol/outer.rs`, `relay/src/reachability.rs`, and
  `relay/src/rooms.rs`.
- Tests added: none; this is a comment-only change and existing tests provide
  the behavioral regression coverage.
- Discrepancies from design: none. `cargo fmt` reflowed existing layout in
  touched sources, including test code, without changing any test assertions
  or behavior; this was necessary for `cargo fmt --check`.
- Adjacent issues parked: none.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
  (122 unit, 57 integration, and 0 doctests), `cargo build`, and
  `cargo doc --no-deps` all passed. The required accented-Latin Portuguese
  grep returned no matches in `relay/src/`.
- Rationale: documented only the audited handwritten public boundary, retained
  generated protocol output untouched, and kept error docs tied to the actual
  fail-fast mappings rather than payload semantics.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- relay/src/`).

### Findings (adjudicated)
- **Important — duplicated summary + incomplete `# Errors` in `parse_hello`** (`relay/src/auth/challenge.rs`): the doc comment had two summary lines (a leftover from translation) and the `# Errors` section omitted `AuthError::Json`, which propagates from `parse_hello_bootstrap`. Collapsed to one summary and added the `AuthError::Json` (malformed JSON) variant. **Fixed.**
- No other findings; translation complete, no behavior/contract/identifier drift. Wire-stable literals untouched.

### Verification of fixes
- `cargo fmt --check` clean.
- `cargo clippy -- -D warnings` clean.
- `cargo test` green (20 passed).

### Verdict
Approve. Advanced `review → done`.
