---
id: epic-rebrand-to-outpost-pi-mechanical-rename-extension-rename
kind: story
stage: implementing
tags: [rebrand, pi-extension]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
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
- [ ] `corepack pnpm --dir pi-extension typecheck` clean
- [ ] `corepack pnpm --dir pi-extension test` green
- [ ] `corepack pnpm --dir pi-extension build` succeeds
- [ ] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `pi-extension/` are only excluded wire-stable literals
