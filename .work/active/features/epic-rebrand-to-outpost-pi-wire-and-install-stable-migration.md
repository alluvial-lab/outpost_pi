---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
kind: feature
stage: implementing
tags: [rebrand, pi-extension, app, relay, cockpit, security, lifecycle]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Wire-stable & install-stable identifier migration (the breaking 0.1.0 slice)

## Brief

The rebrand's **breaking-change** slice: the three wire/install-stable
identifiers and the version reset that pairs them as one release. These are
stability boundaries, not cosmetic strings — renaming them is a one-time
migration gated on the 0.1.0 release boundary.

1. **Auth domain string** — `remote-pi-relay-auth-v1\n` →
   `outpost-pi-relay-auth-v1\n` (keep `v1` suffix). Defined in relay
   `challenge.rs`, extension `relay_client.ts`, app `ws_transport.dart`,
   and `PROTOCOL.md`/`CHANGELOG.md`/`AGENTS.md` prose.
2. **Cockpit control-RPC discriminator** — `\x00remote-pi-ctrl:` →
   `\x00outpost-pi-ctrl:`. Schema-defined in
   `protocol/schema/cockpit-control.schema.json`, emitted by the extension
   `CTRL_PREFIX` constant, consumed by cockpit, documented in
   `cockpit/docs/rpc-protocol.md` and `docs/DECISIONS.md`, with fixtures in
   `protocol/fixtures/cockpit/cockpit-control.jsonl` and a cockpit test.
3. **Install identifiers** —
   - Android `applicationId`: `work.jacobmoura.remotepi` →
     `dev.kevoun.outpostpi`
   - iOS `PRODUCT_BUNDLE_IDENTIFIER`: `work.jacobmoura.remotepi.app` →
     `dev.kevoun.outpostpi.app`
   - `remote_pi_identity` plugin Android namespace: `dev.remotepi.identity`
     → `dev.kevoun.outpostpi.identity` (and the package directory rename +
     Kotlin source path move `dev/remotepi/identity/` →
     `dev/kevoun/outpostpi/identity/`).
4. **Version reset to 0.1.0** across all manifests:
   `pi-extension/package.json` (0.6.0→0.1.0), `app/pubspec.yaml`
   (1.2.0+7→0.1.0), `relay/Cargo.toml` (0.2.2→0.1.0),
   `cockpit/pubspec.yaml` (1.5.1+9→0.1.0), `site/package.json` (0.1.0, hold),
   `rp-s3/Cargo.toml` (0.1.0, hold).

Per the locked strategic decision, the new relay accepts **only** the new
auth string (hard cutover, no dual-accept window). The phone requires a
one-time uninstall + reinstall (existing install cannot upgrade in place).

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi`
- Position in epic: **the breaking release-boundary slice.** All four
  identifier migrations + the version reset ship together as one paired
  release (`app-0.1.0 ↔ relay-0.1.0 ↔ extension-0.1.0`), following the
  same version-pairing discipline as the existing
  `app-v1.2.0 ↔ relay-0.2.0` and `relay-0.2.0 ↔ extension-0.6.0` pairs.

## Dependency on the mechanical-rename feature
This feature has **no hard `depends_on`** on
`epic-rebrand-to-outpost-pi-mechanical-rename`: the wire-stable literals
and version fields are disjoint from the cosmetic strings, so the two
slices can proceed in parallel. However, they must **coordinate** at
release time — the mechanical rename and this breaking slice should land
in the same 0.1.0 release so the shipped artifact is consistently named.
The mechanical-rename feature's exclusion list is the contract that keeps
them disjoint during development.

## Foundation references
- `docs/SPEC.md` — "Hard constraints" (Ed25519 identity, relay semantics),
  "External interfaces" (wire protocol, transports)
- `docs/ARCHITECTURE.md` — Cockpit↔pi control RPC section (discriminator),
  Components diagram
- `PROTOCOL.md` — the auth domain-separation section (paired wire change)
- Root `AGENTS.md` — "Paired wire changes" (deploy order: relay first, then
  reload/restart extension, then sideload app)
- Parent epic `## Strategic decisions` — auth string, cutover, applicationId,
  versioning.

## Design decisions (locked 2026-07-11 feature-design)

- **Cockpit↔extension control-path discriminators — rename all of them.**
  The cockpit-control schema family carries the NUL-prefix
  `\x00remote-pi-ctrl:`, the structured type `remote_pi_control`, and five
  `customType` event strings (`remote-pi:relay-state`,
  `remote-pi:name-assigned`, `remote-pi:pair-code`, `remote-pi:paired`,
  `remote-pi:mesh-revoked`). All are renamed: `\x00outpost-pi-ctrl:`,
  `outpost_pi_control`, `outpost-pi:relay-state`, etc. A half-rebranded
  wire is the worst of both worlds; this is the one breaking release where
  full consistency is cheap.
- **JSON Schema vendor key + `$id` URIs — rename both.** `x-remote-pi` →
  `x-outpost-pi` across all 9 schema files; `$id` URIs
  `https://remote-pi.dev/schemas/...` → `https://kevoun.com/schemas/...`
  (operator's domain; the `$id` is a schema-internal identifier, not
  resolved at runtime, so a resolving host is not required). Full
  consistency across the schema source.
- **`remote_pi_identity` plugin — full rename to `outpost_pi_identity`.**
  Directory, pubspec `name`, Dart library file, and Kotlin class
  `RemotePiIdentityPlugin` → `OutpostPiIdentityPlugin` all rename, in
  addition to the Android namespace. Internal package, not published, but
  consistency across the one breaking release is cheaper than lingering
  `remote_pi_identity` references.

## Architectural choice

**Schema-source-first, then regenerate, then hand-edit the non-generated
emitters/consumers.** The protocol schema (`protocol/schema/`) is the single
source of truth per the generated-contracts principle; the TS/Dart/Rust
generated files are derived. So the discriminator rename flows: edit the
schema → run codegen → the generated files update mechanically → then
hand-edit the non-generated source that emits/consumes those strings (the
extension's `CTRL_PREFIX`, `STRUCTURED_CONTROL_TYPE`, and `customType`
string literals; cockpit's `rpc_event.dart` enum + `pairing_gateway_impl.dart`
dispatch + `pi_rpc_process.dart` constant; relay's auth constant).

The auth domain string and the install identifiers are NOT schema-derived
(auth lives as raw byte constants in three languages; applicationId/bundle
live in build configs) — those are pure hand-edits.

This beats the alternative (a flat scripted replace across all files) because
the schema-source-first path keeps the generated/derivative invariant intact:
if you sed the generated files without updating the schema, the next codegen
run reverts them and `check:protocol` fails.

## Implementation Units

### Unit 1: Protocol schema rename (the source of truth)
**File**: `protocol/schema/*.json` (10 files: `remote-pi.schema.json`,
`manifest.json` description, `cockpit-control.schema.json`,
`relay-control.schema.json`, `cross-pc.schema.json`, `app-pi-server.schema.json`,
`app-pi-client.schema.json`, `relay-outer.schema.json`,
`defs/agent-envelope.schema.json`, `defs/common.schema.json`,
`defs/app-pi-common.schema.json`)
**Story**: `…-schema-source`

- Rename all `$id` URIs `https://remote-pi.dev/schemas/...` →
  `https://kevoun.com/schemas/...`
- Rename vendor key `x-remote-pi` → `x-outpost-pi` everywhere it appears
- In `cockpit-control.schema.json`: rename the NUL-prefix pattern
  `\u0000remote-pi-ctrl:` → `\u0000outpost-pi-ctrl:`, the `controlVerb`
  `x-outpost-pi.prefix`, and all five `customType` consts
  (`remote-pi:relay-state` → `outpost-pi:relay-state`, etc.) plus the
  `customType` enum list in `customMessage`
- Update `remote-pi.schema.json` `title`/`description` prose to
  `Outpost-Pi`; rename the umbrella file itself? **No** — keep
  `remote-pi.schema.json` filename rename in the mechanical-rename feature's
  scope (it's a path, not a wire string); but the `$id` and `title` inside
  it are this feature's. (Coordinate: the mechanical rename must not break
  the `$ref: ./remote-pi.schema.json` paths mid-migration. See Risks.)
- Update `protocol/fixtures/cockpit/cockpit-control.jsonl` to the new
  discriminators

**Acceptance Criteria**:
- [ ] `corepack pnpm --dir protocol check` passes (fixtures validate
      against renamed schemas)
- [ ] `corepack pnpm --dir protocol list-types` emits the new `outpost-pi:` /
      `outpost_pi_control` discriminators
- [ ] Zero remaining `remote-pi.dev` `$id` or `x-remote-pi` keys in
      `protocol/schema/`

---

### Unit 2: Generated protocol artifacts (regen)
**Files**: `pi-extension/src/protocol/generated/protocol.generated.ts`,
`app/lib/protocol/generated/protocol.g.dart`,
`relay/src/protocol/generated/*.rs`
**Story**: `…-regen-generated` (depends on `…-schema-source`)

- Run the codegen: `corepack pnpm --dir pi-extension generate:protocol` (TS),
  plus the Dart and Rust generators per their documented commands
- Verify the generated unions now carry `outpost-pi:relay-state` etc. and
  `outpost_pi_control`
- **Do NOT hand-edit generated files** — if a discriminator didn't update,
  the schema in Unit 1 was missed, not the generator

**Acceptance Criteria**:
- [ ] `corepack pnpm --dir pi-extension check:protocol` passes (generated ==
      schema source, no drift)
- [ ] Generated TS/Dart/Rust carry zero `remote-pi:` / `remote_pi_control`
      discriminator literals

---

### Unit 3: Relay auth constant + hard-cutover test
**File**: `relay/src/auth/challenge.rs` (line 107:
`RELAY_AUTH_DOMAIN_PREFIX`)
**Story**: `…-relay-auth` (depends on `…-schema-source`; parallel with Units 4-6)

- `pub const RELAY_AUTH_DOMAIN_PREFIX: &[u8] = b"remote-pi-relay-auth-v1\n";`
  → `b"outpost-pi-relay-auth-v1\n";`
- Update the doc comment's cross-reference to the app's
  `relayAuthDomainPrefix` (the app file path stays; the constant value
  changes in Unit 6)
- Add a **hard-cutover compatibility test**: a relay auth attempt signed
  over the OLD `remote-pi-relay-auth-v1\n` prefix is rejected as
  `InvalidSig`; the same signature over the new prefix verifies. This pins
  the locked strategic decision (no dual-accept).

**Acceptance Criteria**:
- [ ] `cargo test -p relay` passes including the new cutover test
- [ ] `cargo clippy -- -D warnings` clean

---

### Unit 4: Extension emitters + control constants
**Files**: `pi-extension/src/index.ts` (`CTRL_PREFIX` line 168,
`STRUCTURED_CONTROL_TYPE` line 170, `customType` string literals at lines
271, 439, 1065, and command-surface files),
`pi-extension/src/extension/command_surface/control_commands.ts` (line 110),
`pi-extension/src/extension/command_surface/local_mesh_commands.ts` (line 377),
`pi-extension/src/extension/command_surface/pairing_coordinator.ts` (line 326),
`pi-extension/src/transport/relay_client.ts` (line 14:
`RELAY_AUTH_DOMAIN_PREFIX`)
**Story**: `…-extension-emitters` (depends on `…-regen-generated`)

- `CTRL_PREFIX = "\x00remote-pi-ctrl:"` → `"\x00outpost-pi-ctrl:"`
- `STRUCTURED_CONTROL_TYPE = "remote_pi_control"` → `"outpost_pi_control"`
- `RELAY_AUTH_DOMAIN_PREFIX = Buffer.from("remote-pi-relay-auth-v1\n")` →
  `"outpost-pi-relay-auth-v1\n"`
- All `customType: "remote-pi:relay-state"` literals → `"outpost-pi:..."`
- Update `extension.test.ts` assertions (lines 4474-4545 region) to the new
  `outpost-pi:` strings

**Acceptance Criteria**:
- [ ] `corepack pnpm --dir pi-extension typecheck` clean
- [ ] `corepack pnpm --dir pi-extension test` green
- [ ] `corepack pnpm --dir pi-extension build` succeeds

---

### Unit 5: Cockpit consumers
**Files**: `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` (line 384),
`cockpit/lib/app/cockpit/domain/entities/rpc_event.dart` (lines 174-178, the
enum values + the PT doc comments referencing them),
`cockpit/lib/app/cockpit/data/relay/pairing_gateway_impl.dart` (lines 92, 106),
`cockpit/test/data/pi_rpc_process_control_test.dart`,
`cockpit/test/data/rpc_event_mapper_test.dart`
**Story**: `…-cockpit-consumers` (depends on `…-regen-generated`)

- `_controlEnvelopeType = 'remote_pi_control'` → `'outpost_pi_control'`
- `rpc_event.dart` enum: `relayState('remote-pi:relay-state')` →
  `relayState('outpost-pi:relay-state')`, etc. for all five
- `pairing_gateway_impl.dart` `case 'remote-pi:pair-code':` →
  `'outpost-pi:pair-code':`, `'remote-pi:paired':` → `'outpost-pi:paired':`
- Update both test files' string literals

**Acceptance Criteria**:
- [ ] `flutter analyze` (in `cockpit/`) clean
- [ ] `flutter test` (in `cockpit/`) green

---

### Unit 6: App auth constant + install identifiers + plugin rename
**Files**: `app/lib/data/transport/ws_transport.dart` (line 34:
`relayAuthDomainPrefix`),
`app/android/app/build.gradle.kts` (lines 25, 39: namespace + applicationId),
`app/ios/Runner.xcodeproj/project.pbxproj` (6 occurrences of
`work.jacobmoura.remotepi`),
`app/packages/remote_pi_identity/` → `app/packages/outpost_pi_identity/`
(directory rename via `git mv`),
`app/packages/outpost_pi_identity/pubspec.yaml` (`name:`),
`app/packages/outpost_pi_identity/lib/remote_pi_identity.dart` →
`lib/outpost_pi_identity.dart`,
`app/packages/outpost_pi_identity/android/build.gradle.kts` (namespace),
`app/packages/outpost_pi_identity/android/src/main/kotlin/dev/remotepi/identity/`
→ `dev/kevoun/outpostpi/identity/` (dir rename), Kotlin files inside:
  `RemotePiIdentityPlugin.kt` → `OutpostPiIdentityPlugin.kt` + class rename,
  `BlockStoreStore.kt` (package decl update),
`app/pubspec.yaml` (path dependency on the renamed package)
**Story**: `…-app-install-and-plugin` (depends on `…-regen-generated`; the
install-identifier and plugin-rename parts are independent of the schema but
batched for the single breaking release)

- `relayAuthDomainPrefix = utf8.encode('remote-pi-relay-auth-v1\n')` →
  `'outpost-pi-relay-auth-v1\n'`
- Android app: `namespace`/`applicationId` `work.jacobmoura.remotepi` →
  `dev.kevoun.outpostpi`
- iOS bundle id (all 6 pbxproj occurrences): `work.jacobmoura.remotepi.app` →
  `dev.kevoun.outpostpi.app`
- Plugin: `git mv` the directory, rename pubspec `name:` to
  `outpost_pi_identity`, rename Dart lib file + its `library` declaration,
  move Kotlin sources to the new package path, rename the plugin class,
  update the app's `pubspec.yaml` path dependency name

**Acceptance Criteria**:
- [ ] `flutter analyze` (in `app/`) clean
- [ ] `flutter test` (in `app/`) green
- [ ] Android namespace/applicationId and iOS bundle id all read
      `dev.kevoun.outpostpi*`; Kotlin compiles under the new package path

---

### Unit 7: Version reset to 0.1.0 + durable docs roll-forward
**Files**: `pi-extension/package.json`, `app/pubspec.yaml`,
`relay/Cargo.toml`, `cockpit/pubspec.yaml` (site + rp-s3 already 0.1.0, hold),
`AGENTS.md`, `PROTOCOL.md`, `CHANGELOG.md`
**Story**: `…-version-and-docs` (depends on all prior units; the release-binding
unit)

- `pi-extension/package.json` version `0.6.0` → `0.1.0`
- `app/pubspec.yaml` `1.2.0+7` → `0.1.0+0`
- `relay/Cargo.toml` `0.2.2` → `0.1.0`
- `cockpit/pubspec.yaml` `1.5.1+9` → `0.1.0+0`
- Roll `AGENTS.md` "Paired wire changes" section forward in-place: the
  `app-v1.2.0 ↔ relay-0.2.0` and `relay-0.2.0 ↔ extension-0.6.0` pairings
  become the new `app-0.1.0 ↔ relay-0.1.0 ↔ extension-0.1.0` pairing for
  the `outpost-pi-relay-auth-v1` rename (current truth, no migration prose)
- Roll `PROTOCOL.md` auth-domain section forward to the new prefix literal
- `CHANGELOG.md`: add the 0.1.0 Outpost-Pi rebrand entry (changelog is the
  one durable doc that IS historical — entries accumulate, not rewritten)

**Acceptance Criteria**:
- [ ] All four manifests read `0.1.0` (site/rp-s3 hold at 0.1.0)
- [ ] `AGENTS.md` paired-wire table reflects the 0.1.0 pairing + new auth
      string, with no stale `remote-pi-relay-auth-v1` or old version refs
- [ ] `PROTOCOL.md` carries `outpost-pi-relay-auth-v1` current-truth

## Implementation Order

1. `…-schema-source` (Unit 1) — the source of truth; everything regen-related
   depends on it
2. `…-regen-generated` (Unit 2) — pure codegen run; depends on 1
3. In parallel after 2:
   - `…-relay-auth` (Unit 3)
   - `…-extension-emitters` (Unit 4)
   - `…-cockpit-consumers` (Unit 5)
   - `…-app-install-and-plugin` (Unit 6)
4. `…-version-and-docs` (Unit 7) — the release-binding unit; depends on 1-6

## Testing

- **Unit tests**: each story's owning-subproject test suite (relay `cargo
  test`, extension `pnpm test`, app/cockpit `flutter test`)
- **Hard-cutover compatibility test** (Unit 3): pins that the relay rejects
  old-auth signatures — the testable assertion of the locked strategic
  decision. This is the single most important new test in this feature.
- **Protocol contract test**: `corepack pnpm --dir protocol check` validates
  fixtures against renamed schemas; `check:protocol` confirms generated ==
  schema (no drift)
- **Integration**: the deploy-order smoke (relay → extension restart → app
  sideload) confirms the paired release works end-to-end. This is a manual
  operator step documented in AGENTS.md, not an automated gate.

## Risks

- **Schema `$ref` path vs filename rename split.** This feature renames the
  `$id` URI and `title` inside `remote-pi.schema.json` but NOT the file's
  path/name (that's the mechanical-rename feature). During the window between
  the two features landing, the file is still named `remote-pi.schema.json`
  but its `$id` says `kevoun.com`. The `$ref: ./remote-pi.schema.json` paths
  in the manifest and umbrella schema still resolve correctly (they're
  filesystem-relative, not `$id`-relative), so this is cosmetic drift, not a
  break. Mitigation: note the split in the mechanical-rename feature so it
  completes the filename rename; the two features converge at the 0.1.0
  release.
- **Generated-file drift if schema is missed.** If a discriminator string is
  missed in Unit 1, the codegen in Unit 2 silently keeps the old value and
  `check:protocol` passes (it checks generated-vs-schema, not
  schema-vs-intent). Mitigation: Unit 1's acceptance criterion includes a
  grep asserting zero `remote-pi:` / `x-remote-pi` in `protocol/schema/`.
- **Kotlin package path move breaks the build silently.** Moving
  `dev/remotepi/identity/` → `dev/kevoun/outpostpi/identity/` requires the
  `package` declaration in both `.kt` files to change AND the directory to
  move; a mismatch produces a compile error (good — fail fast), but only if
  `flutter analyze`/the Android build actually runs. Mitigation: Unit 6's
  acceptance criteria require `flutter analyze` clean in `app/`.
- **applicationId irreversibility.** After the first 0.1.0 sideload there is
  no path back to `work.jacobmoura.remotepi` without another phone uninstall.
  This is accepted per the locked strategic decision; flagged here as the
  highest-irreversibility risk. No mitigation — it's the intended cutover.
- **Cross-slice collision with mechanical-rename.** The mechanical-rename
  feature's exclusion list must keep it off `remote-pi-relay-auth`,
  `remote-pi-ctrl`, `remote_pi_control`, `remote-pi:` customTypes,
  `jacobmoura.remotepi`, `x-remote-pi`, and the LICENSE copyright line. If it
  touches any, this feature's units will conflict at merge. Mitigation: this
  feature lands first (it owns the wire-stable literals); the mechanical
  rename's exclusion list is defined relative to this feature's replacements.
