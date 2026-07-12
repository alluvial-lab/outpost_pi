---
id: epic-rebrand-to-outpost-pi-mechanical-rename-app-rename
kind: story
stage: done
tags: [rebrand, app]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# app mechanical rename

## Scope
Unit 3 of the mechanical-rename feature. ~179 occurrences across 69 files.
Rename user-visible strings, session-name default (`remote_pi` → `outpost_pi`),
the debug-log filename `remote_pi_debug.jsonl` → `outpost_pi_debug.jsonl`
(per hard-cutover decision, orphaning existing logs is accepted), and prose.

## Exclusion list (DO NOT TOUCH — owned by wire-stable feature)
- `remote-pi-relay-auth-v1`, `dev.remotepi.peers`/`dev.remotepi.rooms`,
  `remotepi://` URI scheme, `REMOTE_PI_*` env vars, the applicationId/
  bundle id, the `remote_pi_identity` plugin.

## Acceptance Criteria
- [x] `flutter analyze` (in `app/`) clean
- [x] `flutter test` (in `app/`) green
- [x] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `app/` are only excluded wire-stable literals

## Implementation notes

- Renamed app-visible copy, the app widget (`OutpostPiApp`), command/update labels,
  session default (`outpost_pi`), debug export filename (`outpost_pi_debug.jsonl`),
  store listing, and wireframe asset (`Outpost-Pi.html`). Existing debug logs are
  intentionally not migrated.
- Preserved the auth-domain literal and all `remote_pi_identity` package references.
  The verification grep reports only those exclusions.
- Verified with `flutter analyze` (`No issues found`) and `flutter test` (`All tests
  passed`, 683 tests). One preceding full-suite attempt exposed an unrelated flaky
  `sync_service_test` session-sync assertion; its focused rerun passed, and the
  subsequent full rerun passed.
