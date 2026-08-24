---
id: gate-docs-readme-app-version
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-25
---

# Root README pins sideload status to the obsolete app-v0.3.x

## Drift category
readme-staleness

## Location
- Doc: `README.md:22-26`
- Contradicting source: `app/pubspec.yaml:19`

## Current doc text
> Google Play (Android) | _Coming soon — sideload-only as of app-v0.3.x (post-rebrand applicationId)_

## Contradiction
The current app artifact is `0.7.0+12`; the download status is still sideload-only,
but the README's `app-v0.3.x` qualifier is stale and makes the human-facing
release status look three product generations behind.

## Required edit
Keep the accurate store-availability statement, but remove the obsolete version
qualifier or replace it with the current release-neutral distribution wording.

## Implementation

Replaced the obsolete app-v0.3.x qualifier with release-neutral sideload/store wording in `README.md`.
