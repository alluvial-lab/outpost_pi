---
id: gate-docs-protocol-island-scan-rule
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Protocol scan rule still treats generated Dart relay frames as an island

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/scan-protocol-contract/SKILL.md:57-64` and `.agents/skills/scan-protocol-contract/references/undocumented-protocol-island.md:25-36`
- Contradicting source: `app/lib/protocol/generated/relay_frames.g.dart:40-53`

## Current doc text
> Hand-maintained island WITH a documented reason (e.g. `control_frames.dart`) | low | Skip — documented exception
>
> Relay control/presence/rooms frames are not yet in the schema IR, so they remain in the temporary hand-maintained island.

## Contradiction
The current Dart relay-frame projection is generated and decodes
`peer_online`, `peer_offline`, `rooms`, and `room_meta_updated` from the generated
DTO union. `control_frames.dart` is now an adapter over generated relay DTOs, not
the undocumented wire-shape island described by this scan rule.

## Required edit
Update the scan rule and reference example to the current generated relay-frame
boundary, remove the obsolete documented-island exception for these frames, and
retain only genuinely hand-maintained protocol islands.
