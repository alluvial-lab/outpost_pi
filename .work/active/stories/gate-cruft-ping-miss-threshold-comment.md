---
id: gate-cruft-ping-miss-threshold-comment
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: cruft
created: 2026-10-04
updated: 2026-10-04
---

# State-machine comment reports the wrong ping-miss threshold

## Confidence
High

## Category
Stale comment

## Location
`app/lib/data/transport/connection_manager.dart:7` (header block lines 5–12,
which this release already touched for the stall fast-cycle note)

## Evidence
```dart
// failure               (WS close or 2 ping misses)
```
The canonical schema specifies `degradedAfterMissedAppPon
gs: 3` (`protocol/schema/reachability.json:18`), and runtime code checks
`missedPings == 3` (`connection_manager.dart:2203`).

## Removal
Change the comment to describe the three-miss threshold by referring to the
canonical reachability policy. While editing the same header block, drop the
verdict-number/`.work` archaeology from its stall lines (cohesive with
`gate-cruft-verdict-archaeology-comments`, which covers the remaining sites).

## Fixed (2026-10-04)
Header block rewritten: three-missed-ping threshold referenced to the
canonical reachability policy; verdict archaeology dropped from the stall
note (same block). `flutter analyze` clean.
