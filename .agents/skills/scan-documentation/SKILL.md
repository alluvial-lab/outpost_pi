---
name: scan-documentation
description: >
  Outpost-Pi documentation coverage scan. Checks that Always-tier exports
  (per `.agents/skills/documentation-conventions/SKILL.md`) carry meaningful
  native doc comments — JSDoc for TypeScript, dartdoc `///` for Dart, rustdoc
  `///` for Rust. Auto-loads as a gate-refactor rule library via glob
  `scan-*/SKILL.md`. Adapted from the SNC/platform scan-documentation skill.
allowed-tools: Read, Glob, Grep
---

# Documentation Scan

Scan the codebase for missing or inadequate inline documentation per the
convention at `.agents/skills/documentation-conventions/SKILL.md`. The
convention defines a three-tier model (Always / Recommended / Skip) keyed to
**intent**, not type — read it before scanning.

This is a coverage + quality scan: it flags *missing* doc comments on
Always-tier exports and *inadequate* comments that restate types or state the
obvious. Adding a doc comment is always a specific, low-risk,
behavior-preserving change — findings route to the refactor lane.

## Language detection

Per file extension, apply the matching syntax and rule set:

| Extension | Language | Doc syntax | Public-API marker |
|---|---|---|---|
| `.ts`, `.tsx` | TypeScript / React | `/** */` JSDoc | `export` |
| `.dart` | Dart | `///` dartdoc | non-underscore-prefixed top-level declaration; `class`/`mixin`/`enum` members |
| `.rs` | Rust | `///` rustdoc | `pub` / `pub(crate)` |

## Rules

| Rule | Slug | What to check |
|---|---|---|
| Exported function undocumented | `exported-fn` | Always-tier exported function (TS `export fn`, Dart public fn, Rust `pub fn`) without a doc comment |
| Exported type/class undocumented | `exported-type` | Always-tier exported class/type/interface/enum without a doc comment |
| Service contract undocumented | `service-contract` | Function returning `Result`/`Either`/discriminated union (TS, Dart) or `Result<T>` (Rust) without contract doc (preconditions, error behavior) |
| Shared/domain export undocumented | `shared-export` | Export from a shared/domain layer module (`pi-extension/src/protocol`, `app/lib/domain`, `cockpit/lib/.../domain`, `relay/src/` public API) without a doc comment |
| Component/ViewModel undocumented | `component-doc` | Exported React component with 3+ props, or Flutter widget/ViewModel with 3+ params, without a purpose doc |
| Error path undocumented | `error-path` | Function that `throws` (Dart/TS) or returns `Result` (Rust) without `@throws`/`# Errors`/contract note |
| Type-restating doc | `type-restatement` | Doc comment that only restates the signature (`@param {string} id - the id`) — noise that drifts |
| Obvious-description doc | `obvious-description` | Doc that states the obvious (`/// The user model.` on `class User`) — no value |

## Tier filter (skip these — do not flag)

Per the convention's Skip tier, do NOT flag:
- Schema/DTO declarations that restate a wire shape (generated or
  mirror-of-wire structs).
- Barrel `index.ts`/`index.dart` re-exports.
- Test files (`*_test.dart`, `*.test.ts`, `tests/`).
- Self-documenting constants, trivial private helpers (<10 lines).
- Generated code (`.generated.ts`, `protocol/schema/` generated output).
- Flutter widget `build()` overrides (the override contract is fixed).

## Finding format

```
- [ ] **(documentation)** **{slug}**: {one-line description} — {file}:{line} — Fix: add `{syntax}` with {what to document}
```

Group findings by file for readability. Tag all findings `(documentation)`.

## Output

Findings land as refactor-gate items (Fix lane, high confidence). Adding doc
comments is behavior-preserving — nothing needs the Analyze lane. Per the
`gate-refactor` convention, this library declares `findings-route: refactor`
(behavior-preserving), so findings auto-route through the refactor-design
family.

## What this scan does NOT do

- It does not translate PT → EN (that's the `epic-rebrand-to-outpost-pi-en-first`
  epic's job). A PT comment that satisfies the tier + intent rules is not a
  documentation-scan finding; it's an EN-first finding.
- It does not enforce a rendered doc site — Outpost-Pi publishes no external
  API surface, so the scan optimizes for agent + IDE-hover readability.
- It does not mandate ESLint/clippy enforcement — agent-scan only (see the
  convention's rationale).

## Adapted from

SNC/platform `.claude/skills/scan-documentation` (TS-only). Extended to Dart
and Rust; the rule set and tier model transfer, the syntax and public-API
markers are per-language.
