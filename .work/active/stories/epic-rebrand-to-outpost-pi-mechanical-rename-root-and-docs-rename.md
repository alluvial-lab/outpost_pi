---
id: epic-rebrand-to-outpost-pi-mechanical-rename-root-and-docs-rename
kind: story
stage: done
tags: [rebrand, docs]
parent: epic-rebrand-to-outpost-pi-mechanical-rename
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# root + .github + shared docs mechanical rename

## Scope
Unit 6 of the mechanical-rename feature. Rename root README, the
`.github/workflows` references (`RemotePi.apk` → `OutpostPi.apk`,
`RemotePiCockpit-...dmg` → `OutpostPiCockpit-...dmg`), `PROTOCOL.md` title
and prose (non-wire-stable sections only — the auth-domain section is owned
by the wire-stable feature's version-and-docs story), `docs/` prose.

## Exclusion list (DO NOT TOUCH)
- `CHANGELOG.md` historical entries (changelog is historical; only the new
  `0.1.0` entry uses Outpost-Pi, added by the wire-stable feature's docs story)
- `AGENTS.md` paired-wire-changes section (owned by wire-stable docs story)
- `PROTOCOL.md` auth-domain section (owned by wire-stable docs story)
- `protocol/schema/` filenames and `$id`s (owned by wire-stable Unit 1)
- `scripts/` operator-glue shell comments (per epic decision, leave untouched
  unless they reference a renamed product identifier that breaks a runtime path)

## Acceptance Criteria
- [x] `.github/workflows` references updated to `OutpostPi*` artifact names
- [x] Root README uses `Outpost-Pi` wordmark
- [x] `PROTOCOL.md` title is `Outpost-Pi` (auth-domain section left for wire-stable)
- [x] Verification grep + manual review of the diff

## Implementation notes

- Renamed README copy, URLs, install/command examples, release artifacts, and shared-doc prose to the Outpost-Pi forms in the feature replacement table.
- Kept `PROTOCOL.md`'s `remote-pi-relay-auth-v1` auth-domain literal unchanged. The remaining `remote_pi` references in `docs/VISION.md` and `docs/DECISIONS.md` identify the historical fork/upstream; `\x00remote-pi-ctrl:` remains the excluded control-RPC discriminator.
- Ran the requested grep verification and `git diff --check`; manually reviewed the scoped diff. No build gate applies to this documentation/workflow-only story.
