---
id: gate-docs-release-uat-outpost-command
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Release UAT runbook invokes the retired remote-pi command

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/release-uat.md:36-38`
- Contradicting source: `pi-extension/src/extension/command_surface/commands.ts:24-34`

## Current doc text
> `/remote-pi` footer shows connected [and] `/remote-pi pair` renders the QR.

## Contradiction
The extension registers `outpost-pi` and its subcommands; pairing guidance in the command surface directs operators to `/outpost-pi pair`. The UAT runbook would make the release checkpoint execute unavailable commands.

## Required edit
Replace retired command names with `/outpost-pi` and `/outpost-pi pair` throughout the runbook while preserving the live-smoke acceptance checks.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline runbook repair; command registration provides an exact executable name.
- **Change:** Replaced every `/remote-pi` invocation in `docs/release-uat.md` with `/outpost-pi`, including the live footer and pairing checks.
- **Verification:** Confirmed `pi-extension/src/extension/command_surface/commands.ts` registers `outpost-pi` and the runbook contains no `/remote-pi` command. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — smoke acceptance behavior is unchanged apart from the executable command name.
