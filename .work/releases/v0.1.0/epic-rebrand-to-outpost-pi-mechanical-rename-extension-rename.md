---
id: epic-rebrand-to-outpost-pi-mechanical-rename-extension-rename
kind: story
stage: done
tags: [rebrand, pi-extension]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# pi-extension mechanical rename

## Scope
Unit 1 of the mechanical-rename feature. ~963 occurrences across 80 files.
Apply the replacement table to code-internal strings, log prefixes, the npm
`name`/`bin` fields, internal labels, README, CLAUDE.md, daemon docs prose.

## Exclusion list (DO NOT TOUCH — owned by wire-stable feature)
- `remote-pi-relay-auth-v1`, `remote-pi-ctrl`, `remote_pi_control`,
  `remote-pi:relay-state` and the 4 other customTypes, `x-remote-pi`,
  `remote-pi.dev`, `dev.remotepi.*`, `dev.remotepi.supervisord`,
  `REMOTE_PI_*`/`REMOTEPI_*`, the LICENSE copyright line,
  `protocol/generated/`, `protocol/schema/`.

## Acceptance Criteria
- [x] `corepack pnpm --dir pi-extension typecheck` clean
- [ ] `corepack pnpm --dir pi-extension test` green (sandbox process-exit issue; assertions pass)
- [x] `corepack pnpm --dir pi-extension build` succeeds
- [x] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `pi-extension/` are only excluded wire-stable literals

## Implementation notes

- Renamed 74 tracked `pi-extension/` files: package/bin and CLI labels,
  code-internal strings, daemon/service artifacts, tests, and extension docs.
  Wire-stable literals and `src/protocol/generated/` were left unchanged.
- Renamed the protocol-codegen API's PascalCase `RemotePi` identifiers to
  `OutpostPi` in its source, CLI, and tests because the extension schema-parity
  test imports that API.
- Verification used `COREPACK_HOME=/home/agent/projects/remote_pi/.tmp/corepack-home`.
  Typecheck and build succeeded. Vitest reported 51 passing files / 829 passing
  tests / 3 skipped with a temporary writable `REMOTE_PI_HOME`; its process did
  not terminate in the sandbox after reporting the green summary because of an
  existing open-handle issue.
- The verification grep found 30 remaining matches, all allowlisted wire-stable
  literals (auth domain, control discriminator/type, or customType events).
