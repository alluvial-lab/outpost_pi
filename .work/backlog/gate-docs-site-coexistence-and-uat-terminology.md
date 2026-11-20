---
id: gate-docs-site-coexistence-and-uat-terminology
created: 2026-11-20
updated: 2026-11-20
tags: [site, docs, workflow]
---

# Reconcile site local-mesh coexistence docs and Workbench terminology in `docs/release-uat.md`

Parked from `v0.14.0` release-gate `docs` / `cruft` scan (medium/low, non-blocking).

## Evidence pointers

- `site/src/app/docs/page.tsx:862-889` (`"Two Pi processes can't share a directory"`) and `site/src/app/tutorials/mesh-local/page.tsx:45-50` (`"One agent per folder"`) still contradict `(cwd, name)` lock ownership and `#N` same-folder coexistence (`pi-extension/src/session/cwd_lock.ts:174-185`, `site/src/app/tutorials/claude-mesh/page.tsx:248-264`); `site/src/app/docs/page.tsx:257-260` also lists `get_messages` as a native Pi tool.
- `docs/release-uat.md:101,104,155-160` retains retired `agile-workflow` terminology (`release-deploy`, `release_uat`) and removed item slugs (`story-ci-android-emulator-test-job`, `feature-public-flip-branding-and-exposure`).
- Minor adjacent doc/comment cleanup: `AGENTS.md:126` stale skill-authoring caveat; `e2e/README.md:119` link into transient `.work/active/`; `pi-extension/src/session/leader_election.ts:54` missing JSDoc on `ProbeOptions`; `pi-extension/README.md:622` retired `plan/26` heading; stale `.orchestration/INSTRUCTIONS.md` / `gate-refactor` pointers and `scripts/emulator-scanner-smoke.sh:14` `.work/active/stories/` comment.
