---
id: gate-docs-changelog-v090-user-visible-drain
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: docs
created: 2026-08-26
updated: 2026-08-26
---

# CHANGELOG has no v0.9.0 entry for the shipped user-visible changes

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:12`
- Contradicting source: `app/lib/data/sync/sync_service.dart:438-542`; `pi-extension/src/extension/fresh_session_shutdown.ts:48-119`; `cockpit/lib/main.dart:53-78`; `site/package.json:5-12`

## Current doc text
> `## [Unreleased]` followed immediately by the prior `v0.8.1` release entry.

## Contradiction
The v0.9.0 bundle contains user-visible and operator-visible changes with no release entry: durable owner-prompt recovery and restart-fence retry behavior, mobile typed slash actions, Cockpit atomic JSON state with legacy migration, the browser-backed site baseline, and the cross-surface theme/brand contract. The release changelog therefore does not describe the release being gated.

## Required edit
Add a v0.9.0 changelog entry covering the released fresh-session/outbox/retry contract, mobile actions, Cockpit JSON migration, site browser baseline, and theme/brand contract changes, plus the user-visible fixes in the bound items. Keep the entry as the active release truth and update the comparison links when the release tag is cut.

## Closure (2026-08-26)

Resolved by release-deploy Phase 5.5: the v0.9.0 changelog entry was drafted
from the 41 bound items, confirmed by the operator, and prepended to
CHANGELOG.md (features / fixes / security / internal grouping).
