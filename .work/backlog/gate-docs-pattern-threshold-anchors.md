---
id: gate-docs-pattern-threshold-anchors
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Asymmetric-threshold pattern has shifted changed-file examples

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/asymmetric-threshold-stabilization.md:23-61`
- Contradicting source: `app/lib/ui/chat/chat_page.dart:134-149`; `app/lib/data/transport/reachability_adapter.dart:83-100`

## Current doc text
> Composer hysteresis is cited at `chat_page.dart:131-143`, and reachability hysteresis at `reachability_adapter.dart:50-60`.

## Contradiction
The v0.11.0 status and liveness additions shifted both changed-file examples. The composer implementation begins at line 134 and extends past the cited range, while the reachability methods now begin at line 83; the old range no longer identifies the documented threshold behavior.

## Required edit
Refresh the two anchors and quoted snippets to the current compact-composer and reachability threshold implementations. Preserve the entry/exit hysteresis contract without adding historical notes.
