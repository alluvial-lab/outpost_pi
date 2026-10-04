---
id: release-v0.12.1
kind: release
stage: quality-gate
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

## Gate runs
(populated during Phase 4)
