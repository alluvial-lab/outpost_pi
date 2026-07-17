---
kind: story
release_binding: null
parent: feature-repair-current-state-docs
stage: done
id: gate-docs-readme-stale-boilerplate
tags: [documentation]
depends_on: []
gate_origin: docs
created: 2026-07-01
updated: 2026-07-16
---

# Cockpit README is stale/boilerplate and not project-specific

## Location
cockpit/README.md:1-17

## Issue
README content is still generic Flutter starter text and no longer reflects Cockpit's local usage, run/build conventions, or features.

## Recommendation
Replace with an operator-facing Cockpit README (project purpose, setup/build/run, remote-pi control surface, key commands, and links to canonical docs).
