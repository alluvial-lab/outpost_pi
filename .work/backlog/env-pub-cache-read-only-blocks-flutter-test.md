---
id: env-pub-cache-read-only-blocks-flutter-test
created: 2026-07-12
updated: 2026-07-11
tags: [env, testing, app, cockpit]
---

# `~/.pub-cache` is read-only → `flutter test`/`flutter pub get` blocked

## Problem

`~/.pub-cache` lives on a read-only filesystem in this sandbox. `flutter test`
and `flutter pub get` fail before running:

```
Creation failed, path = '/home/agent/.pub-cache' (OS Error: Read-only file system, errno = 30)
Failed to update packages.
```

This blocks `flutter test` for both `app/` and `cockpit/`. `flutter analyze
--no-pub` works (deps already resolved in `.dart_tool/`), so static analysis
passes, but the test suites can't execute.

## Impact

- The mechanical-rename stories for `app/` and `cockpit/` are verified by
  `flutter analyze` (clean) but NOT by `flutter test` (blocked).
- This is an environment/sandbox issue, not a product bug — report the exact
  prerequisite rather than faking the test (per testing-integrity rules).

## Suspected cause / fix direction

This is likely the pi-sandbox extension restricting writes outside allowed
paths. Per the global AGENTS.md note ("If you hit unexpected tool egress
blocks... raise it rather than papering over it"), this should be surfaced to
the operator, not worked around.

Possible fix: allow writes to `~/.pub-cache` (or set `PUB_CACHE` to a
writable location like `.tmp/pub-cache`, mirroring the `COREPACK_HOME`
workaround for pnpm).

## Related

- The pnpm equivalent (`COREPACK_HOME` on read-only `/home/agent/.local-state`)
  was worked around by pointing `COREPACK_HOME` at a writable project-local
  `.tmp/` dir. A similar `PUB_CACHE` override may work for Flutter but was not
  attempted to avoid over-fighting the environment.
