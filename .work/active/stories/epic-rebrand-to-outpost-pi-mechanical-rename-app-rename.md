---
id: epic-rebrand-to-outpost-pi-mechanical-rename-app-rename
kind: story
stage: implementing
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
- [ ] `flutter analyze` (in `app/`) clean
- [ ] `flutter test` (in `app/`) green
- [ ] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `app/` are only excluded wire-stable literals
