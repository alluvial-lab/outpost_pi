---
id: epic-durable-transcript-ownership-retire-rederivation
kind: feature
stage: done
tags: [pi-extension, refactor]
parent: epic-durable-transcript-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log, feature-canonical-transcript-timestamp-ownership, epic-durable-transcript-ownership-durable-native-events]
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# F4 — Retire SDK-message re-derivation + two-source contract

## Brief

Remove the lossy re-derivation path; formalize SDK-messages-vs-extension-entries
(LLM-context vs transcript) as the documented consistency contract with a
reconciliation test surface. Terminal feature — lands last, after F1-F3 prove
durable coverage.

## Epic context

Depends on F1 (foundation), F2 (timestamp migration), F3 (native events) —
retirement is only safe when durable coverage is complete.

## Simplification opportunity

IS the simplification: deletes the re-derivation code path and its
divergence-prone reconciliation, replacing it with a narrow documented
boundary. Black-box refactor (transcript output identical when durable data
is complete).

## Two-source contract

**SDK messages remain authoritative for LLM context; extension entries are authoritative for transcript.** A `message_end` SDK fact may produce a durable
extension entry at the live boundary, but reopen never treats SDK-message
projection as general transcript authority. The two-pass reconciler reads valid
v1 extension entries first and consults SDK messages only for unmatched
pre-durable facts in mixed-era sessions (or where a corrupt/unsupported entry
cannot claim authority).

## Refactor design

One cohesive checkpoint, `epic-durable-transcript-ownership-retire-rederivation-two-source-boundary`, owns the change.

- **Current state:** live `message_end` calls a legacy append path for user,
  assistant, and tool-result messages; the same SDK mapper is exported through
  runtime/test adapters; transitional fallback aliases remain in the aggregate.
- **Target state:** current user and assistant transcript facts cross the v1
  durable recorder before visibility; execution hooks remain the sole tool
  transcript producers. SDK-to-transcript mapping becomes private to the
  active-branch reconciler and is named/scoped as pre-durable fallback only.
- **Elimination:** remove the general live fallback append API, aggregate aliases
  and fallback-upgrade bookkeeping, the direct SDK-message-to-history adapter,
  and duplicated mapper tests. Retain the two-pass SDK fallback itself because
  persisted pre-upgrade sessions are verified external data.
- **Black-box boundary:** durable-era `session_history` remains byte-equivalent
  across real file reopen; mixed-era SDK-only prefixes still render, while later
  matching v1 entries win one-for-one.
- **Risk:** medium — live ordering/identity and old-session replay are both
  load-bearing. Rollback is the single checkpoint commit; no persistence or wire
  format changes are introduced.

## Acceptance criteria

- [x] The contract text above also appears verbatim in the reconciliation-owning module.
- [x] Durable-era real-file reopen output is identical and contains no SDK-derived competing facts.
- [x] Mixed-era real-file reopen retains pre-upgrade SDK fallback and durable-authoritative suffixes.
- [x] SDK fallback is reachable only through reconciliation/test fixtures, not the live recording path.
- [x] Dead aliases/adapters are deleted with importer/search evidence.
- [x] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passes from `pi-extension/`.

## Implementation order

1. Add reopen-equivalence and mixed-era contract tests.
2. Make live SDK-derived user/assistant facts durable and remove tool re-derivation.
3. Collapse fallback and delete dead aliases/adapters, then run the full suite.

## Implementation summary

- Execution capability: `sol/high`; one host-side owner retained the live/reopen
  identity context across the atomic checkpoint.
- Review: direct integrated black-box and stale-reference review found no
  material residual. Independent review is deferred to the invoking host because
  this worker context has no subagent adapter.
- Current `message_end` user and assistant-text facts record through v1 before
  transcript visibility. SDK tool-call/toolResult messages no longer enter the
  transcript; durable execution hooks are their sole authority.
- `reconcileTranscriptContextEntries` now owns the documented two-source
  boundary. Its SDK mapper is private and reachable only for unmatched
  pre-durable facts. Valid v1 facts win; corrupt/future entries cannot suppress
  old-session fallback.
- Deleted: general live fallback methods, fallback-upgrade state, transitional
  aggregate aliases, unused append helper, direct SDK-message history adapter,
  runtime wrapper, tool-message live re-derivation, and duplicated adapter-only
  tests. Importer/stale-name grep is empty after deletion.
- Retained: the private two-pass pre-durable mapper, raw compaction conversion,
  corrupt/unsupported-entry fallback, and the SDK-fixture test adapter. Real
  pre-upgrade JSONL sessions, mixed-era prefixes, and existing test histories
  prove each remains required.
- Reopen evidence: focused aggregate/projection/session replacement tests passed
  92 tests; real-file cases pin complete durable-authoritative equivalence and
  SDK-only-prefix plus v1-suffix mixed-era behavior.
- Final suite: typecheck passed; all 59 Vitest files passed (1079 passed,
  3 skipped); build passed. No version bump, generated output, push, or adjacent
  backlog item.
