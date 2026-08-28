---
id: gate-docs-app-claude-axis-alignment
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# App guidance still documents the removed axisAlignment analyzer issue

## Drift category
repo-skill-staleness

## Location
- Doc: `app/CLAUDE.md:41-43`
- Contradicting source: `app/lib/ui/chat/widgets/input_bar.dart:824-830` (removed by the bound cleanup)

## Current doc text
> `flutter analyze` in `app/` emits one known `deprecated_member_use` `info` for the `axisAlignment` argument in `lib/ui/chat/widgets/input_bar.dart`; the source comment explains the Flutter pin.

## Contradiction
The v0.11.0 cleanup replaced `SizeTransition.axisAlignment` with explicit `alignment` and removed the analyzer ignore and pin-era comment. The documented analyzer issue and source comment no longer exist, so this guidance tells agents to tolerate a problem that the current app no longer has.

## Required edit
Remove the obsolete exception and state the current zero-warning `flutter analyze` expectation. Do not preserve the old pin explanation as history.
