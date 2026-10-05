---
id: release-v0.12.1
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Release v0.12.1

Fix-lane patch cut (two-lane policy): launcher safe-defaults + metronome
app-side attribution/recovery fixes. Diagnosis evidence: verdicts #1–#9 in
`story-fix-connection-metronome-death` (stays active — diagnosis story, not a
bundle member).

## Bound items

- `story-claude-launcher-safe-local-qualification` (done) — pi-extension CLI:
  no injected `--dangerously-*` flags (operator opt-in via passthrough),
  headless wizard fail-fast, docs (help/README/site).
- `story-fix-metronome-phantom-close-teardown` (done) — app: dart-synthesized
  1002/1001 report as `streamError` (+ `dartProtocolError`/`dartPingWatchdog`),
  never `serverCloseFrame`.
- `story-fix-post-strike-recovery-ladder` (done) — app: same-peer connect
  join (cancel race), `handshakeStall` fast-cycle class (1s retries, frozen
  ladder rung, transport-owned 12s auth deadline).

Excluded from binding: 7 v0.12.0 gate items (already bound to v0.12.0);
archived cruft stubs at `stage: drafting` (parked unimplemented findings —
not done work; binding would pend readiness; stay unbound per two-lane
selective binding).

## UAT

### Round 1 — rc.1 (2026-10-04, captures 23:00:57 + 23:16:46, relay paired)
- Attribution ✓ (streamError/dartProtocolError both strikes).
- Recovery ✗ — fast-cycle never engaged; wedge shape pre-upgrade/full-dead-path;
  factory `_CancelledError`/`TimeoutException` (transport kind) beat the 9s
  classification; ladder climbed, 11× _CancelledError, recovery ≈ wedge
  (11min/4min). Fix: `story-fix-recovery-factory-seam` (rc.2 delta).

## Gate runs
- **gate-security** (2026-10-04) — 0 critical / 0 high; 2 medium (MCP inbox unbounded [release-relevant, unbound per routing — operator may bind]; tmp-config symlink path [ambient]) → backlog; 1 low (auth-deadline unhandled error after cancellation — reproduced in new code, marked blocking-by-judgment, FIXED: timer disarmed at cleanup start).
- **gate-docs** (2026-10-04) — 13 findings (6 foundation-doc assertions + 7 pattern-skill staleness), ALL fixed in-pass: VISION/DECISIONS/PROTOCOL Claude-wrapper present tense, reachability stall exception qualified in DECISIONS/ARCHITECTURE/schema companion, 7 pattern file:line refs refreshed.
- **gate-tests** (2026-10-04) — 1 critical (production timeout composition defeated handshakeStall classification; FIXED: 9s deadline + hoisted consts + ordering seam test), 1 medium (join adoption/room-binding assertions; strengthened same pass). Test-integrity pass: 0 issues; no tautological tests.
- **battery** (patch scope) — pairing suite ✓ (18 tests + redaction canaries); live failure lane ✓; live state-shapes lane ✓.
- **gate-patterns** (2026-10-04) — 2 patterns codified (evidence-local-failure-classification, join-in-flight-operations); 1 inconsistency (new join tests' `_settle()` sleep vs deterministic-completion-barriers → unbound drafting story). Tracking item bound.
- **gate-refactor** (2026-10-04) — 0 findings; 3 libraries (boundaries, lifecycle, protocol-contract) loaded, all 13 reference rules applied to the 11 bundle files. Adjacent note: scanner independently confirmed the production factory-timeout ordering issue now tracked by gate-tests.
(populated during Phase 4)

## Shipped items

Bodies retained on disk under `.work/releases/v0.12.1/` (retain-bodies).

| id | kind | git ref |
|----|------|---------|
| story-claude-launcher-safe-local-qualification | story | 0f71e21ba |
| story-fix-metronome-phantom-close-teardown | story | 0f71e21ba |
| story-fix-post-strike-recovery-ladder | story | 0f71e21ba |
| story-fix-recovery-factory-seam | story | 0f71e21ba |
| gate-patterns-v0.12.1 | story | 0f71e21ba |
| gate-cruft-ping-miss-threshold-comment | story | 0f71e21ba |
| gate-tests-production-timeout-composition | story | 0f71e21ba |
| gate-docs-vision-claude-wrapper | story | 0f71e21ba |
| gate-docs-decisions-claude-future | story | 0f71e21ba |
| gate-docs-protocol-claude-future | story | 0f71e21ba |
| gate-docs-reachability-stall-docs | story | 0f71e21ba |
| gate-docs-pattern-line-refresh | story | 0f71e21ba |
| gate-security-auth-deadline-unhandled-error | story | 0f71e21ba |

## Ship record

- Date shipped: 2026-10-04 (local) / 2026-10-05T04:2xZ
- Mapping: tag-based (v0.12.1 pushed; release published from the rc.2 draft
  with fat + slim-arm64 +29 artifacts)
- Total items shipped: 13 (4 fix stories, 9 gate items — gate findings
  fixed in-pass; 5 medium/low findings parked unbound in backlog)
- Gate totals: 6 gates; 0 critical/0 high shipped; the 1 critical tests
  finding + 1 blocking-by-judgment low were fixed pre-ship; UAT rounds:
  rc.1 (attribution verified; recovery fix gap found), rc.2 (single-strike
  recovery 11s verified; sustained-wedge cycling covered by tests, field
  confirmation open)
- Battery: pairing suite + live failure + state-shapes lanes green; full
  app suite 1,076 green
