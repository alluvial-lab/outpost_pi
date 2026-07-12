---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-extension-emitters
kind: story
stage: implementing
tags: [rebrand, pi-extension]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
---

# Extension control constants + emitters + auth constant

## Scope

Unit 4 of the wire-stable migration feature. Hand-edit the non-generated
extension source that emits/consumes the renamed wire discriminators, and
the extension-side auth constant.

## Units implemented
- Unit 4 (extension emitters)

## Changes
- `pi-extension/src/index.ts`:
  - line 168: `CTRL_PREFIX = "\x00remote-pi-ctrl:"` → `"\x00outpost-pi-ctrl:"`
  - line 170: `STRUCTURED_CONTROL_TYPE = "remote_pi_control"` → `"outpost_pi_control"`
  - `customType` string literals (lines 271, 439, 1065) → `outpost-pi:` prefix
- `pi-extension/src/extension/command_surface/control_commands.ts` (line 110):
  `customType: "remote-pi:name-assigned"` → `"outpost-pi:name-assigned"`
- `pi-extension/src/extension/command_surface/local_mesh_commands.ts` (line 377):
  same rename
- `pi-extension/src/extension/command_surface/pairing_coordinator.ts` (line 326):
  `customType: "remote-pi:pair-code"` → `"outpost-pi:pair-code"`
- `pi-extension/src/transport/relay_client.ts` (line 14):
  `Buffer.from("remote-pi-relay-auth-v1\n")` → `"outpost-pi-relay-auth-v1\n"`
- `pi-extension/src/extension.test.ts` (lines ~4474-4545): update assertions
  to the new `outpost-pi:` strings

## Acceptance Criteria
- [x] `corepack pnpm --dir pi-extension typecheck` clean
- [ ] `corepack pnpm --dir pi-extension test` green — 828 passed, 3 skipped;
      only the known cwd-lock pollution flake failed (`a second same-name agent
      joins as <name>#2`; `.work/backlog/env-ext-test-cwd-lock-ordering-flake.md`)
- [x] `corepack pnpm --dir pi-extension build` succeeds (regenerates `dist/`)
- [x] `grep -rn 'remote-pi-ctrl\|remote_pi_control\|remote-pi-relay-auth\|remote-pi:relay-state\|remote-pi:name-assigned\|remote-pi:pair-code\|remote-pi:paired\|remote-pi:mesh-revoked' pi-extension/src/` returns nothing

## Implementation notes
- Files changed: `pi-extension/src/index.ts`,
  `pi-extension/src/extension/command_surface/control_commands.ts`,
  `pi-extension/src/extension/command_surface/local_mesh_commands.ts`,
  `pi-extension/src/extension/command_surface/pairing_coordinator.ts`,
  `pi-extension/src/transport/relay_client.ts`,
  `pi-extension/src/extension.test.ts`, and
  `pi-extension/src/session/sdk_session_projection.test.ts`.
- Tests added: none; existing discriminator assertions and fixtures were updated
  to the Outpost-Pi wire names.
- Verification: typecheck and build passed. The full suite reported 828 passed,
  3 skipped, and only the documented cwd-lock flake. A targeted rerun remained
  affected by the same polluted cwd lock (`first.ok` was false), so no unrelated
  test or lock cleanup was bundled.
- Discrepancies from design: the `remote-pi:mesh-revoked` emitter and the SDK
  session projection test fixture also required renaming to satisfy the story's
  zero-stale-discriminator grep.
- Adjacent issues parked: none; the sole test failure is already tracked by
  `env-ext-test-cwd-lock-ordering-flake`.
