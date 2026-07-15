---
id: story-en-first-residual-maintained-surfaces
kind: story
stage: implementing
tags: [rebrand, docs, workflow, cockpit, app, site]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate residual maintained surfaces to English

## Brief

Finish the EN-first promise on maintained surfaces omitted by the original epic decomposition. The shipped application code is green, but release automation, dormant product tooling, compatibility agent definitions, and package documentation still contain Portuguese prose and user-facing output.

Translate the remaining maintained text in:

- `.github/workflows/app-release.yml`;
- `.github/workflows/cockpit-release.yml`;
- `.claude/agents/scout-{app,cockpit,pi-extension,relay,site}.md`;
- `rp-s3/Cargo.toml`, `rp-s3/Dockerfile`, and `rp-s3/src/main.rs`;
- `app/packages/outpost_pi_identity/README.md` and its example configuration comments;
- any remaining shipped site or product text found by the final verification scan.

Preserve intentional multilingual Unicode/codec fixtures such as `café` and `olá`, historical records, binaries, generated/vendor state, and the original epic's `scripts/` operator-glue exclusion. Translation must preserve workflow behavior, shell interpolation, identifiers, error conditions, and test semantics.

## Verification

Run syntax or owning-project checks for every touched executable surface, then repeat the EN-first repo scan with explicit exclusions. The final record must list every retained non-English occurrence and why it is intentional.
