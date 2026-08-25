---
id: gate-docs-pattern-failure-first-anchors-v080
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Failure-first pattern anchors drifted in the transcript and reconnect tests

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/failure-first-regression-tests.md:47-103`
- Contradicting source: `app/test/data/sync/sync_service_test.dart:1745-1775`; `app/test/ui/chat/chat_viewmodel_test.dart:833-875`

## Current doc text
> Close the authoritative turn, then inject its late duplicate — `sync_service_test.dart:1448-1485`.
>
> Preserve a send through the missing-session window — `chat_viewmodel_test.dart:828-865`.

## Contradiction
The durable transcript/error additions moved the late-duplicate regression to `sync_service_test.dart:1745-1775`; the reconnect-hydration send test begins at `chat_viewmodel_test.dart:833` and the cited range no longer identifies its documented setup. Agents following the pattern land in unrelated test code.

## Required edit
Refresh the two stale test anchors and snippets to the current late-echo and reconnect-identity-window tests. Leave the unchanged concurrent-connect example anchored only if its current range still matches.
