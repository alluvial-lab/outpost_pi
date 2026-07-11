---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
kind: feature
stage: drafting
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

## Design notes (for `/agile-workflow:feature-design`)

- **Deploy order** (from root AGENTS.md): relay first → reload/restart the
  extension (full pi restart, not `/reload`, to load the new auth constant) →
  sideload the app. Mixed versions break the WS handshake.
- **The applicationId change is irreversible on the phone**: after the first
  0.1.0 sideload, there is no path back to `work.jacobmoura.remotepi` without
  another uninstall. Verify the chosen `dev.kevoun.outpostpi` identifier
  before shipping.
- **Regenerate protocol artifacts**: the `cockpit-control.schema.json` change
  must flow through the generated-protocol codegen
  (`protocol/schema/` → TS/Dart/Rust generated) and update the
  `protocol/fixtures/cockpit/cockpit-control.jsonl` fixtures + the cockpit
  test that asserts the prefix.
- **The iOS bundle id** appears in `Runner.xcodeproj/project.pbxproj` in
  multiple build configs (Runner + RunnerTests) — all must change together.
- **AGENTS.md / PROTOCOL.md / CHANGELOG.md prose** references the old auth
  string and old paired versions; these docs are rolled forward in-place to
  the new `outpost-pi-relay-auth-v1` and `0.1.0` pairing (rolling-foundation,
  current truth, no migration prose).
- A **compatibility test** should assert the relay rejects the old auth
  string (hard-cutover behavior) and accepts the new one.
