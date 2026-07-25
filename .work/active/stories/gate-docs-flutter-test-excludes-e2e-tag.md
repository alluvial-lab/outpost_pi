---
id: gate-docs-flutter-test-excludes-e2e-tag
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# App verification docs still prescribe unfiltered flutter test

## Drift category
repo-skill-staleness + foundation-doc-assertion (merged findings 2+3 from the
2026-07-24 drain-delta docs scan)

## Location
- Doc: `.agents/skills/flutter-mobile/SKILL.md:23-29`, `app/CLAUDE.md:31-38`,
  `AGENTS.md:82-87`, `docs/SPEC.md:118-128`, `.agents/rules/testing-integrity.md:40-46`
- Contradicting source: `.github/workflows/ci.yml:158-160`,
  `app/test/e2e/owner_channel_e2e_test.dart:1-2`, `e2e/README.md:3-12`

## Current doc text
> `flutter test` (unfiltered, as the standard app verification command)

## Contradiction
The ordinary app verification lane now excludes tagged harness E2E tests.
Unfiltered `flutter test` includes tests requiring the Docker/Toxiproxy
pairing harness and fails without E2E_* endpoints. Note for agents on this
VM: full-suite runs want `--concurrency=2` (load-sensitive timing tests).

## Required edit
Make `flutter test --exclude-tags e2e` the normal app verification command
in all five docs, name `e2e/run-pairing.sh` as the dedicated E2E command,
and keep the VM concurrency note where agent-facing (AGENTS.md,
flutter-mobile skill, testing-integrity rule).
