---
id: story-en-first-residual-maintained-surfaces
kind: story
stage: done
tags: [rebrand, docs, workflow, cockpit, app, site]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
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

## Implementation notes

### Files changed

- `.github/workflows/app-release.yml` and `.github/workflows/cockpit-release.yml`: translated comments, step labels, validation errors, release notes, and summaries without changing YAML or shell interpolation.
- `.claude/agents/scout-{app,cockpit,pi-extension,relay,site}.md`: translated the maintained scout definitions and report templates.
- `rp-s3/Cargo.toml`, `rp-s3/Dockerfile`, and `rp-s3/src/main.rs`: translated product metadata, comments/rustdoc, logs, panic text, and `expect` messages without changing behavior.
- `app/packages/outpost_pi_identity/README.md` and example Android/iOS configuration comments: translated the remaining `plan/23` prose references.

### Discrepancies

- None in product behavior. The first `cargo` invocation could not write the read-only default Cargo cache; the required checks passed after using the temporary writable `CARGO_HOME=/tmp/rp-s3-cargo`.

### Verification

- Workflow YAML parsed successfully with `yaml.safe_load_all`; `${{ }}` and shell interpolation were preserved.
- `rp-s3`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` passed.
- Final PT scan (`rg -n '[ãõáéíóúâêôçÃÕÁÉÍÓÚÂÊÔÇ]' .github .claude rp-s3 app/packages/outpost_pi_identity 2>/dev/null`) returned no hits. There are no retained occurrences in the scanned maintained surfaces; codec fixtures, historical records, and excluded `scripts/` were not scanned.

## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).
