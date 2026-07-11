---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-cockpit-consumers
kind: story
stage: implementing
tags: [rebrand, cockpit]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Cockpit control-path consumers

## Scope

Unit 5 of the wire-stable migration feature. Hand-edit the cockpit source
that consumes the renamed cockpit↔extension control discriminators, and
update the cockpit tests.

## Units implemented
- Unit 5 (cockpit consumers)

## Changes
- `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` (line 384):
  `_controlEnvelopeType = 'remote_pi_control'` → `'outpost_pi_control'`
- `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart` (lines 174-178):
  the five enum values `relayState('remote-pi:relay-state')` →
  `relayState('outpost-pi:relay-state')`, etc. Update the PT doc comments
  that reference the old strings (lines 192, 210, 232, 252, 265).
- `cockpit/lib/app/cockpit/data/relay/pairing_gateway_impl.dart`
  (lines 92, 106): `case 'remote-pi:pair-code':` → `'outpost-pi:pair-code':`,
  `'remote-pi:paired':` → `'outpost-pi:paired':`
- `cockpit/lib/app/cockpit/ui/session/agent_session.dart` (line 96): update
  the PT comment referencing `remote-pi:relay-state`
- `cockpit/test/data/pi_rpc_process_control_test.dart` (lines 22, 35):
  `'type': 'remote_pi_control'` → `'outpost_pi_control'`
- `cockpit/test/data/rpc_event_mapper_test.dart` (lines 11, 29, 45, 62, 75,
  84): update the `_customMessage('remote-pi:...')` literals

## Acceptance Criteria
- [ ] `flutter analyze` (in `cockpit/`) clean
- [ ] `flutter test` (in `cockpit/`) green
- [ ] `grep -rn 'remote_pi_control\|remote-pi:relay-state\|remote-pi:name-assigned\|remote-pi:pair-code\|remote-pi:paired\|remote-pi:mesh-revoked' cockpit/lib/ cockpit/test/` returns nothing
