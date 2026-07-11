---
id: epic-rebrand-to-outpost-pi-mechanical-rename-cockpit-rename
kind: story
stage: implementing
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
- [ ] `flutter analyze` (in `cockpit/`) clean
- [ ] `flutter test` (in `cockpit/`) green
- [ ] Verification grep: remaining `remote-pi|remote_pi|Remote Pi|RemotePi` in
      `cockpit/` are only excluded wire-stable literals
