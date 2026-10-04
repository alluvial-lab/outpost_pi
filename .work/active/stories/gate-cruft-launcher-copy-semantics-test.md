---
id: gate-cruft-launcher-copy-semantics-test
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-10-04
updated: 2026-10-04
---

# Array-aliasing test is implementation-bound and unused by the CLI contract

## Confidence
Medium

## Category
Low-value test

## Location
`pi-extension/src/extension/command_surface/standalone_cli.test.ts:24-29`

## Evidence
The "returns a copy — callers cannot mutate the input argv" test pins
non-aliasing behavior no production caller depends on (the launcher spreads
the result immediately). Launcher behavior is unchanged either way.

## Removal
Delete the test unless non-aliasing is made an explicit public API contract.
Keep the positional-CWD and verbatim-passthrough tests.
