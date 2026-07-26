---
id: gate-cruft-savepeersilent-dead-export
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: app-v0.3.0
gate_origin: cruft
created: 2026-07-25
updated: 2026-07-25
---

# savePeerSilent is a dead export

## Confidence
High (whole-repo grep, app-v0.3.0 gate 2026-07-25)

## Evidence
`app/lib/pairing/storage.dart:441` — no production caller remained; mesh
hydration uses `saveMeshPeerMetadata`, conflict repair uses
`restorePeerSnapshotSilent`, and `deletePeerSilent` stays live.

## Implementation notes
Removed `savePeerSilent`; reworded `deletePeerSilent`'s doc link (rationale
now inline); replaced the isolated test with coverage of the surviving
silent mesh API (`saveMeshPeerMetadata` hydrates metadata-only without
emitting mutation intent). Verification: flutter analyze clean;
storage/mesh/debug-log tests 59 green.

## Review
Bounded inline review (orchestrator, 2026-07-25): deletePeerSilent confirmed
live (mesh_sync_service.dart:338,374) before removal; test rewrite asserts
real silent-upsert behavior. Approved -> done.
