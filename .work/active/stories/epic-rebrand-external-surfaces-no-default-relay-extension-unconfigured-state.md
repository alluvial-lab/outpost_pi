---
id: epic-rebrand-external-surfaces-no-default-relay-extension-unconfigured-state
kind: story
stage: done
tags: [rebrand, pi-extension]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Surface an unconfigured relay in the Pi extension

## Scope

Replace the extension's community-default relay resolution with the discriminated
`RelayResolution` contract described by the parent feature. Update every extension
entry point that currently assumes a URL: `/outpost-pi` start and status, the
pairing coordinator, the standalone CLI help, and the Claude MCP mesh bridge.
Keep local UDS mesh operation available when cross-PC relay configuration is absent.

## Acceptance criteria

- [x] `pi-extension/src/config.ts` has no `kDefaultRelayUrl`; resolution remains
  `env > config`, then returns `{ url: null, source: "unconfigured" }`.
- [x] Start paths fail before opening a relay socket and notify the user to run
  `/outpost-pi set-relay <url>` when unconfigured.
- [x] `/outpost-pi status` reports the unconfigured state and the same recovery
  command rather than a fictitious relay URL.
- [x] The standalone CLI's `set-relay` usage does not advertise a default.
- [x] `mcp/mesh_server.ts` skips only its relay bridge and emits an actionable
  stderr diagnostic; its local mesh/broker remains usable.
- [x] Config/extension tests cover absent, config, and env resolution plus
  unconfigured status/start behavior; mocks and docs no longer name the retired
  relay.
- [x] `corepack pnpm typecheck` and relevant Vitest tests pass.

## Implementation notes

- `RelayResolution` is now a configured/unconfigured union. Both extension
  start implementations narrow it before identity lookup and transport creation,
  so no nullable URL reaches WebSocket conversion.
- Status, pairing, the standalone CLI, and the MCP bridge use the same
  `/outpost-pi set-relay <url>` recovery action. MCP starts its local mesh with
  no bridge and writes the configuration diagnostic only to stderr.
- The extension integration fixture retains an explicitly test-only relay for
  unrelated relay lifecycle tests; individual tests opt into the unconfigured
  state. This avoids recreating a production fallback in the resolver mock.
- The pre-existing same-folder lock test now supplies a writable temporary
  `OUTPOST_PI_HOME`, because the sandbox mounts the real lock directory
  read-only; it remains a real UDS lock behavior test.

## Verification

- `corepack pnpm typecheck`
- `corepack pnpm exec vitest run src/config.test.ts src/extension.test.ts`
  (207 tests passed)
