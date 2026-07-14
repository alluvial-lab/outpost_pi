---
id: epic-rebrand-external-surfaces-no-default-relay-extension-unconfigured-state
kind: story
stage: implementing
tags: [rebrand, pi-extension]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Surface an unconfigured relay in the Pi extension

## Scope

Replace the extension's community-default relay resolution with the discriminated
`RelayResolution` contract described by the parent feature. Update every extension
entry point that currently assumes a URL: `/outpost-pi` start and status, the
pairing coordinator, the standalone CLI help, and the Claude MCP mesh bridge.
Keep local UDS mesh operation available when cross-PC relay configuration is absent.

## Acceptance criteria

- [ ] `pi-extension/src/config.ts` has no `kDefaultRelayUrl`; resolution remains
  `env > config`, then returns `{ url: null, source: "unconfigured" }`.
- [ ] Start paths fail before opening a relay socket and notify the user to run
  `/outpost-pi set-relay <url>` when unconfigured.
- [ ] `/outpost-pi status` reports the unconfigured state and the same recovery
  command rather than a fictitious relay URL.
- [ ] The standalone CLI's `set-relay` usage does not advertise a default.
- [ ] `mcp/mesh_server.ts` skips only its relay bridge and emits an actionable
  stderr diagnostic; its local mesh/broker remains usable.
- [ ] Config/extension tests cover absent, config, and env resolution plus
  unconfigured status/start behavior; mocks and docs no longer name the retired
  relay.
- [ ] `corepack pnpm typecheck` and relevant Vitest tests pass.
