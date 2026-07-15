---
id: idea-translate-legacy-orchestration-contracts
kind: story
stage: backlog
tags: [rebrand, docs, i18n, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Translate (or retire) legacy `.orchestration/contracts/` Portuguese docs

## Origin

Surfaced by the `epic-rebrand-to-outpost-pi-en-first` aggregate epic review
(2026-07-15, cross-model fresh-context pass). The reviewer flagged that
`.orchestration/contracts/pairing.md` (212 lines, 60 accented-PT lines) and
`.orchestration/contracts/protocol.md` (241 lines, 77 accented-PT lines)
remain substantially Portuguese despite the EN-first rebrand.

## Why parked, not fixed inline

These files are **legacy orchestration-framework contract docs**, not in the
EN-first epic's owned scope (app/site/relay/pi-extension/cockpit/prose). They
were last touched by pre-rebrand commits (`3587db4 MVP funcional`,
`af8548a`, `0956a74`) and are not referenced as active/current anywhere in
`CLAUDE.md`, `AGENTS.md`, or `.agents/`. The orchestration framework itself
hasn't been used recently (recent `.orchestration/` commits are just results
files from orchestrated runs, not contract updates).

Translating 453 lines of contract docs is a separate work item. The
`.gitignore` comment describing the contracts dir (which IS in the prose
feature's scope) was translated in the epic review fix.

## Options

1. **Translate** `pairing.md` and `protocol.md` to English (if the contracts
   are still a useful reference).
2. **Retire** the `.orchestration/contracts/` dir and remove the
   shared-contract claim from `.gitignore` (if the contracts are obsolete and
   the orchestration framework is no longer in use).

Decide based on whether the orchestration framework is still active. If
retired, also clean `.orchestration/INSTRUCTIONS.md` references in
`CLAUDE.md`.
