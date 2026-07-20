---
id: gate-docs-changelog-extension-020
kind: story
stage: done
tags: [pi-extension, documentation]
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Add the extension-0.2.0 release changelog entry

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:12`
- Contradicting source: `.work/active/features/feature-outbound-buffer-on-peer-offline.md:1`

## Current doc text
> ## [app-v0.2.0] — 2026-07-20

## Contradiction
`CHANGELOG.md` has no `extension-0.2.0` entry although this component release
binds eleven completed Pi-extension items. In particular, the release adds the
bounded known-offline outbound buffer, makes lifecycle/delivery rejection
handling explicit, removes legacy composition seams, and includes the related
stale-context and generated relay-control contract work.

## Required edit
Add one `extension-0.2.0` entry in the established changelog format that
accurately summarizes all eleven bound items and lists their identifiers:
`feature-outbound-buffer-on-peer-offline`,
`feature-piext-lifecycle-delivery-promise-policy`,
`feature-retire-legacy-piext-composition-seams`,
`feature-outbound-buffer-on-peer-offline-bounded-turn-buffer`,
`feature-outbound-buffer-on-peer-offline-ordering-regressions`,
`feature-outbound-buffer-on-peer-offline-presence-lifecycle`,
`feature-outbound-buffer-on-peer-offline-turn-boundary-wiring`,
`gate-refactor-lifecycle-queued-delivery-promise`,
`gate-refactor-protocol-contract-relay-client-island`,
`story-stale-action-boundary-regression-tests`, and
`story-stale-command-ui-notify-guard`.

## Gate execution
Documentation drift audit ran inline at the operator's instruction; scanner
isolation was reduced. The finding was verified from the release binding and
current changelog.
