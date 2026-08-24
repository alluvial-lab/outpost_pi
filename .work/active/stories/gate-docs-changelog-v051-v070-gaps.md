---
id: gate-docs-changelog-v051-v070-gaps
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

# Changelog stops at v0.5.0 while later artifacts shipped

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:12-28`

## Current doc text
> `## [v0.5.0] — 2026-08-15`
>
> All notable changes to Outpost-Pi are documented in this file.

## Contradiction
The repository shipped release artifacts after this heading: relay `0.5.1`,
app `0.5.1+6` through `0.6.3+11`, app `0.7.0+12`, and pi-extension `0.2.0`.
The current release binding also covers the intervening product work, but none of
those versions has a corresponding current changelog entry. The older
`Unreleased — PC mesh foundation` section is not a current v0.7.0 release record.

## Required edit
Add current changelog entries covering the shipped `0.5.1` through `0.7.0`
release sequence, including component artifact versions where the changelog uses
that convention, and roll the active unreleased section forward so the file's
latest state describes the current release.
