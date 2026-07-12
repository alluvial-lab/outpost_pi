---
id: epic-rebrand-to-outpost-pi-mechanical-rename-cockpit-rename
kind: story
stage: done
tags: [rebrand, cockpit]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# cockpit mechanical rename

## Scope
Unit 4 of the mechanical-rename feature. ~190 occurrences across 58 files.
Rename user-visible strings, PT comments referencing the product name, doc
titles, and prose to `Outpost-Pi`/`outpost-pi`.

## Exclusion list (DO NOT TOUCH — owned by wire-stable feature)
- `_controlEnvelopeType`/`remote_pi_control`, the `rpc_event.dart` enum
  customType values, `pairing_gateway_impl.dart` case strings (Unit 5 of
  wire-stable), `REMOTE_PI_*` env-var emitters (Unit 8), the launchd probe
  path `dev.remotepi.supervisord` (Unit 8), generated protocol files.

## Acceptance Criteria
- [x] `flutter analyze` (in `cockpit/`) clean
- [x] `flutter test` (in `cockpit/`) green
- [x] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `cockpit/` are only excluded wire-stable literals

## Implementation notes

- Applied the `Outpost-Pi`/`outpost-pi` mechanical rename across the Cockpit's
  user-facing UI, CLI/process integration, packaging metadata, documentation,
  comments, and tests; renamed `remote_pi_resolver.dart` to
  `outpost_pi_resolver.dart` and its public helpers accordingly.
- Preserved the wire-stable control type, control-prefix and custom-event
  literals, their tests and explanatory comments, the `REMOTE_PI_*` variable,
  and the `dev.remotepi.supervisord` launchd probe. Generated protocol files
  and historical `CHANGELOG.md` entries were left untouched.
- Verification from `cockpit/` with `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache`:
  `flutter analyze` completed with no issues; `flutter test` completed with
  237 passing tests. The final tracked-file grep leaves only the documented
  wire-stable literals (plus excluded historical changelog entries).
