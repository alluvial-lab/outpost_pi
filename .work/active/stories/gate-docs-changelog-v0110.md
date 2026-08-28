---
id: gate-docs-changelog-v0110
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: docs
created: 2026-08-28
updated: 2026-08-28
---

# Root changelog has no v0.11.0 entry for the bound release work

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:10-12`
- Contradicting source: `.work/active/release-v0.11.0.md:14-39`

## Current doc text
> `## [Unreleased]`
>
> The next version section is `## [v0.10.1]` / the existing prior release history; no `v0.11.0` section records the current release bundle.

## Contradiction
The release is bound to twelve completed items covering retry-liveness UX, pair-code clipboard copying, background/orchestrating status, transcript-hydration ordering, stale-IME recovery, SDK/toolchain cleanup, mobile extension-command verification, and system-status delivery. The root changelog has no v0.11.0 entry, so the release's human-facing change record does not describe the shipped bundle.

## Required edit
Add a `v0.11.0` section in the root `CHANGELOG.md` with concise feature/fix/internal entries covering the bound release work. Keep `Unreleased` above it and describe current shipped behavior rather than progress history.
