---
id: feature-outpost-pi-identifier-convergence
kind: feature
stage: done
tags: [rebrand, protocol, pi-extension, app, relay, docs, testing]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Finish active Outpost-Pi identifier convergence

## Brief

Complete the active product-identity conversion missed by the core rebrand review. Outpost-Pi still carries pre-rebrand names in the canonical protocol package and schema, generated-contract descriptions, active fixtures, and extension test/runtime aliases. These are maintained product identifiers rather than provenance and should converge on `Outpost-Pi`, `outpost-pi`, or `outpost_pi` as appropriate.

This feature absorbs the backlog findings `gate-cruft-legacy-protocol-identifiers` and `rebrand-cross-client-auth-contract-test`. The latter belongs here because the auth-domain name is duplicated across Dart, TypeScript, and Rust; a shared vector or generated contract must protect the hard-cutover identifier from future half-renames.

## Scope boundary

Design and implementation should inventory active occurrences before editing and distinguish product identity from intentional legacy evidence. Expected surfaces include:

- `protocol/package.json`, the umbrella schema filename and references, schema titles/descriptions, `protocol/schema/manifest.json`, and `protocol/README.md`;
- active protocol fixtures and protocol-codegen tests that display or describe the old product name;
- active `remotePi*` extension aliases and test-harness names that no longer describe a compatibility boundary;
- current agent/operator documentation that still names the live product or workspace “Remote Pi”;
- the cross-language `outpost-pi-relay-auth-v1\n` contract and tests;
- the live `remote-pi-data` relay volume name, which requires an explicit state-preserving migration decision rather than a blind rename or silent abandonment.

Preserve unchanged:

- `LICENSE`, `NOTICE`, README acknowledgements, and factual provenance;
- historical `.work/`, release, research, and changelog records;
- legacy-rejection tests and pre-rebrand cleanup commands whose old literal is the behavior under test;
- genuine third-party dependency coordinates;
- wire/install compatibility literals that are intentionally retained and documented;
- absolute `/home/agent/projects/remote_pi` checkout paths until the separate cwd migration.

## Design handoff

The design pass should derive a concrete keep/change allowlist, choose the canonical schema/package names, decide how the auth-domain contract is shared across languages, and define a non-destructive relay-volume migration or an explicit compatibility retention rule. No global search-and-replace is acceptable.

## Design decisions (2026-07-14, operator-confirmed)

- **Auth-domain contract: both generation + cross-component test (Q4).** The canonical `outpost-pi-relay-auth-v1\n` string lives in one schema-level location; each consumer imports/derives from it where the toolchain makes that trivial (TS via a shared module, Rust via the generated `protocol/generated` module), and a shared-vector contract test across app/extension/relay enforces that all three sign over the identical bytes. Generation prevents origin drift; the test catches copy drift if someone bypasses codegen.
- **`remote-pi-data` Docker volume: defer to cwd migration, then wipe (Q5).** The legacy volume name stays unchanged for now to avoid disrupting the live relay. At cwd-migration time the operator recreates the container with a new `outpost-pi-data` volume and wipes the old one — no state-preserving migration is needed (mesh membership re-registers on next connect). Documented as deferred, not abandoned.
- **Extension `remotePi` aliases: rename outright (Q6).** The `remotePi` parameter names in `install.ts`/`install.test.ts` and the `remotePiTestHarness`/`__remotePiTestHarness` exports are internal identifiers with no wire/compatibility meaning. Rename to `outpostPi` / `outpostPiTestHarness` / `__outpostPiTestHarness`.

## Architectural choice

Mechanical identifier convergence with a SSOT-first ordering: rename the protocol package and umbrella schema first (the root of the `$ref` graph), then propagate titles/descriptions, then fix fixtures and codegen test descriptions, then the extension aliases, then the auth-domain contract sharing, then docs. The auth-domain contract is the only design-bearing unit; everything else is careful find-and-replace against an explicit allowlist.

## Implementation Units

### Unit 1: Protocol package and schema convergence
**File**: `protocol/package.json`, `protocol/schema/remote-pi.schema.json` → `protocol/schema/outpost-pi.schema.json`, all `protocol/schema/*.json` titles/descriptions, `protocol/schema/manifest.json`, `protocol/README.md`
**Story**: `feature-outpost-pi-identifier-convergence-protocol-schema`

Rename the private npm package `@remote-pi/protocol-schema` → `@outpost-pi/protocol-schema`; `git mv` the umbrella schema file and update its `$id`; update all `$ref` paths and cross-references; replace "Remote Pi" titles/descriptions with "Outpost-Pi" across every schema file; update `manifest.json` descriptions and `README.md`.

Preserve: the legacy `remote-pi-relay-auth-v1\n` literal in `relay/src/auth/auth_test.rs:128` (behavior under test — legacy rejection). Preserve the `kevoun.com` `$id` domain (already migrated).

**Acceptance Criteria**:
- [ ] `rg 'remote-pi|Remote Pi|@remote-pi' protocol/` returns only the legacy auth literal in test files (documented as intentional).
- [ ] `corepack pnpm --dir protocol check` passes.
- [ ] `corepack pnpm --dir protocol generate:rust:check` passes (regenerated output is byte-identical after the title/description rename, since generated Rust derives from the schema but the rename must not change wire types).

### Unit 2: Fixtures and codegen test descriptions
**File**: `protocol/fixtures/app-pi/server-messages.jsonl`, `tools/protocol-codegen/src/index.test.ts`
**Story**: `feature-outpost-pi-identifier-convergence-protocol-schema` (same story — small, same surface)

Update the `session_name` in the fixture from `remote_pi · repo` to `outpost_pi · repo`; update codegen test descriptions ("real Remote Pi schema emits…") to "Outpost-Pi". Preserve the `mkdtemp` temp-dir prefixes (`remote-pi-generated-protocol-import`) as harmless internal strings, or rename for consistency.

### Unit 3: Extension alias rename
**File**: `pi-extension/src/daemon/install.ts`, `pi-extension/src/daemon/install.test.ts`, `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/index.ts`
**Story**: `feature-outpost-pi-identifier-convergence-extension-aliases`

Rename `remotePi` param → `outpostPi` in `install.ts` (both `installOutpostPi` and the Windows variant); rename `remotePiTestHarness` → `outpostPiTestHarness` and `__remotePiTestHarness` → `__outpostPiTestHarness` across the test harness, composition root, and re-exports in `index.ts`.

**Acceptance Criteria**:
- [ ] `rg 'remotePi|__remotePi' pi-extension/src/` returns no hits.
- [ ] `corepack pnpm typecheck && corepack pnpm test` pass from `pi-extension/`.

### Unit 4: Auth-domain contract sharing + cross-component test
**File**: `protocol/schema/` (canonical location), `pi-extension/src/transport/relay_client.ts`, `relay/src/auth/challenge.rs`, `app/lib/data/transport/ws_transport.dart`, new cross-component test
**Story**: `feature-outpost-pi-identifier-convergence-auth-contract`

Establish the canonical auth-domain prefix string in one schema-level location. Derive the TS and Rust constants from the generated protocol module where trivial; the Dart constant stays local (Flutter has no codegen path to the TS schema) but is covered by the shared-vector test. Add a cross-component contract test (repo-level, or per-component with a shared fixture) asserting each client signs over `outpost-pi-relay-auth-v1\n` ++ nonce — the same byte vector.

Preserve the legacy `remote-pi-relay-auth-v1\n` literal in `auth_test.rs:128` as the rejection-path fixture.

**Acceptance Criteria**:
- [ ] The auth-domain prefix string is defined in exactly one schema-level place; TS and Rust consume it via the generated module (or a shared module if codegen of a byte constant proves impractical — documented).
- [ ] A cross-component test verifies all three clients (app/extension/relay) sign over the identical `outpost-pi-relay-auth-v1\n` prefix bytes.
- [ ] All subproject test suites pass.

### Unit 5: Documentation and current-state vocabulary
**File**: `CLAUDE.md`, `AGENTS.md` (operational vocabulary like "Remote Pi code/product bugs"), `docs/agent-reference-surface.md`, `protocol/schema/reachability.md`, `pi-extension/src/protocol/session_scope.ts:1`, `app/lib/domain/entities/remote_session_ref.dart:1` (doc comment)
**Story**: `feature-outpost-pi-identifier-convergence-protocol-schema` (docs touched alongside their owning surface) + `feature-outpost-pi-identifier-convergence-auth-contract` (PROTOCOL.md trust-model correction is out of scope per the exclusion list — see Risks)

Replace live-product "Remote Pi" references in maintained docs/comments with "Outpost-Pi" where the reference describes the current product, not provenance. Preserve provenance lines in `AGENTS.md:12`, `docs/DECISIONS.md:40`, `docs/VISION.md:9,66`.

**Acceptance Criteria**:
- [ ] `rg 'Remote Pi' docs/ AGENTS.md CLAUDE.md` returns only intentional provenance/historical lines, each justified.

## Implementation Order
1. `feature-outpost-pi-identifier-convergence-protocol-schema` (Units 1, 2, 5-docs) — no deps
2. `feature-outpost-pi-identifier-convergence-extension-aliases` (Unit 3) — no deps, parallel with 1
3. `feature-outpost-pi-identifier-convergence-auth-contract` (Unit 4) — no deps, parallel with 1+2

All three stories are independent (disjoint file sets) and can run in parallel.

## Testing
- Protocol: `corepack pnpm --dir protocol check && corepack pnpm --dir protocol generate:rust:check`
- Extension: `corepack pnpm typecheck && corepack pnpm test` (from `pi-extension/`)
- Relay: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` (from `relay/`)
- App: `flutter analyze && flutter test` (from `app/`)
- Cross-component auth test: new test, location TBD by implementation (repo-level or per-component with shared fixture)

## Risks
- **PROTOCOL.md trust-model correction is explicitly out of scope** for this feature (it was scoped out of the follow-up review). The current-state protocol/security doc still describes pairing as Owner-signed/ephemeral-app-key. That is a separate docs story, not identifier convergence. Flagged here so an implementer does not expand scope.
- **Generated Rust output may change** if schema titles/descriptions flow into generated code. The `generate:rust:check` step catches this; if the generated file changes, it must be regenerated and committed in the same story.
- **Cross-component test placement**: there is no existing repo-level test harness spanning Dart/TS/Rust. The implementation may need a shared fixture file + per-component test, or a script. This is a design-bearing unit — implement carefully.

## Keep-list (do NOT change)
- `LICENSE`, `NOTICE`, README acknowledgements
- Historical `.work/`, release records, research attestation, CHANGELOG prose
- `relay/src/auth/auth_test.rs:128` legacy `remote-pi-relay-auth-v1\n` literal (rejection test)
- Genuine `jacobaraujo7/*` dependency coordinates
- `remote-pi-data` Docker volume name (deferred to cwd migration per Q5)
- Absolute `/home/agent/projects/remote_pi` checkout paths
- `cockpit/CHANGELOG.md:33` historical release-identity record

## Review (2026-07-15)

**Verdict**: Approve with comments

**Blockers**: none remaining. Deep verification found a stale `KnownErrorCode` assertion in `tools/protocol-codegen/src/index.test.ts`; it was corrected inline and the five protocol-codegen tests pass.

**Important**:
- `story-wire-protocol-codegen-tests-into-check` — wire the currently orphaned protocol-codegen unit suite into canonical verification.
- `story-refresh-current-protocol-security-docs` — correct the explicitly out-of-scope pairing trust-model drift and stale generated-contract progress prose.
- `story-document-deferred-relay-volume-cutover` — preserve the confirmed legacy-volume/cwd-migration decision in the durable operator runbook.

**Nits**: none

**Notes**: Substrate-mode deep review by a fresh-context Codex reviewer. Phase 1 ran completeness/complementary convergence across the feature design, all three child stories, aggregate implementation commits, acceptance criteria, package/private-consumer paths, and the keep-list. Phase 2 then attacked schema/codegen drift, auth-byte ownership, actual signer/verifier call paths, test execution and lifecycle, package/release behavior, and operational documentation. No second fresh reviewer mechanism was exposed inside this delegated context, so both ordered phases used the same fresh reviewer; concrete claims were rechecked directly and stabilized after the failing codegen test was repaired and rerun. Verification passed: protocol fixtures + Rust generation drift check; TypeScript generation drift check; protocol-codegen unit tests (5/5); extension typecheck + 838 tests (3 skipped); relay fmt/clippy + all tests; app analyze + 698 tests. The protocol package remains `private: true`, has no tracked consumers by package name, and the schema rename leaves no active old `$ref`/`$id` path. TS/Rust derive the auth prefix from schema-generated modules; Dart is the one documented local copy and is chained to the same schema-backed fixture. Preserve-list audit passed: legacy rejection literal, provenance/acknowledgement lines, genuine `jacobaraujo7/*` coordinates, historical records, `remote-pi-data`, and checkout paths were not rewritten by the target commits.

