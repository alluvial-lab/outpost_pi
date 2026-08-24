---
id: gate-docs-pattern-pane-teardown-anchor
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

# Pane-teardown pattern points at terminal paste code

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/awaited-pane-teardown-contract.md:60-70`
- Contradicting source: `cockpit/lib/app/cockpit/ui/session/terminal_session.dart:128-133`

## Current doc text
> Terminal session awaits its stream and child process before base close — `terminal_session.dart:109-114`.

## Contradiction
The cited range is now the terminal clipboard-paste implementation. The
resource-owning `close()` method moved to lines 128-133, so the documented
teardown contract is not reachable at its stated anchor.

## Required edit
Refresh the terminal close anchor and snippet to the current awaited
subscription/process teardown.
