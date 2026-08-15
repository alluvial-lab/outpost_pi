---
id: gate-refactor-cockpit-control-island
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, pi-extension]
---

# Cockpit control commands remain a handwritten protocol island

Post-hoc v0.5.0 refactor-gate finding (protocol-contract library,
`undocumented-protocol-island` rule). Confidence: Medium. Ambient (pre-existing;
the bundle only touched adjacent surfaces).

## Location
`cockpit/lib/app/cockpit/domain/entities/pi_command.dart:16` —
`PiControlCommandName` manually repeats the command vocabulary already
defined in `protocol/schema/cockpit-control.schema.json`; serialization
consumed in `pi_rpc_process.dart`.

## Work
Extend protocol code generation to emit the Cockpit Dart command enum +
control-envelope DTO; consume the generated types. Routes through
story/feature design per the scan libraries' `findings-route: none` (the
fix is not black-box-preserving).
