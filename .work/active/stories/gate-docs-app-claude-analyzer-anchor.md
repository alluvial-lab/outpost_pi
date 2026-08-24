---
id: gate-docs-app-claude-analyzer-anchor
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-25
---

# App analyzer guidance points at the old input-bar line

## Drift category
repo-skill-staleness

## Location
- Doc: `app/CLAUDE.md:44-45`
- Contradicting source: `app/lib/ui/chat/widgets/input_bar.dart:832-835`

## Current doc text
> `lib/ui/chat/widgets/input_bar.dart:806` (`axisAlignment`; explanatory comment at line 802).

## Contradiction
The documented `axisAlignment` info and its explanatory comment moved to lines
832-835 in the current input bar after the compact-composer and accessibility
changes. The command remains valid, but the exact anchor now lands on unrelated
code.

## Required edit
Refresh the known analyzer-info location and explanatory-comment line to the
current source, or describe the known info without a brittle line number.

## Implementation

Removed the brittle line anchors and documented the `axisAlignment` analyzer info in `app/CLAUDE.md` by source path.
