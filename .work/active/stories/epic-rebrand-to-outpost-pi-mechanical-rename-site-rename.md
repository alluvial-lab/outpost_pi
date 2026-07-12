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
- [ ] `pnpm --dir site lint` clean (blocked: `pnpm` is unavailable; `corepack pnpm` cannot open its SQLite store in this environment)
- [ ] `pnpm --dir site build` succeeds (blocked by the same pnpm environment failure)
- [x] `grep -rn 'remote-pi\|remote_pi\|Remote Pi\|RemotePi' site/` returns nothing

## Implementation notes

- Applied the replacement table across all tracked text files in `site/`: 29 files and 352 substitutions (kebab, snake, prose, and PascalCase forms).
- Confirmed no `dev.remotepi.*` or `remote-pi-relay-auth` literal exists under `site/`; `git diff --check -- site` is clean.
- The required lint/build commands could not start: bare `pnpm` is not on `PATH`; `corepack pnpm --dir site lint` fails before linting with `[ERR_SQLITE_ERROR] unable to open database file` in the read-only Corepack store.
