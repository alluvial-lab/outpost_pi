---
id: epic-rebrand-to-outpost-pi-mechanical-rename-site-rename
kind: story
stage: implementing
tags: [rebrand, site]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# site mechanical rename

## Scope
Unit 2 of the mechanical-rename feature. ~276 occurrences across 29 files.
Pure marketing/docs surface — no wire-stable literals. Rename all
`remote-pi`/`Remote Pi` to `outpost-pi`/`Outpost-Pi`.

## Acceptance Criteria
- [ ] `pnpm --dir site lint` clean
- [ ] `pnpm --dir site build` succeeds
- [ ] `grep -rn 'remote-pi\|remote_pi\|Remote Pi\|RemotePi' site/` returns nothing
