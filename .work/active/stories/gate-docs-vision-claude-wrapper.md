---
id: gate-docs-vision-claude-wrapper
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: docs
created: 2026-10-04
updated: 2026-10-04
---

# VISION still excludes the Claude mesh wrapper

## Drift category
foundation-doc-assertion (High, release-relevant)

## Location
Doc: `docs/VISION.md:52-53` ("Pi-only. No Claude Code, OpenCode, Goose, or
Aider targets.")
Contradicting: `outpost-pi claude` is a supported optional terminal-only
Claude mesh adapter.

## Required edit
Pi remains the core/mobile harness; `outpost-pi claude` is an optional
terminal-only mesh adapter for Claude Code, not a general multi-harness
control plane. Replace the absolute exclusion in place.
