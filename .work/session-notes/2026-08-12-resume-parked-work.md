# 2026-08-12 — RESUME HERE: parked work after v0.4.0 ship

A fresh-context agent should read this **first** to pick up where the 2026-08-12
session left off. The session shipped v0.4.0 and surfaced follow-ups; this is the
prioritized resume list.

## Backstory (1 minute)
- **v0.4.0 shipped + deployed today** (extension, relay, app live; cockpit
  intentionally skipped — unused surface). Full narrative + decisions:
  `session-notes/2026-08-12-v040-ship-unified-versioning-tiered-gates.md`.
- **`CONVENTIONS.md` changed today:** unified product versioning (one `vX.Y.Z`,
  per-component semver retired) + a trialed **tiered release-gate model** (full
  gates on feature work, security-only regression on gate-origin work).

## Git state — do this first
```
git push origin main          # 3 local commits unpushed (pairing-e2e story, session-note addendum, this note)
```
`origin/main` is behind by those 3. v0.4.0 tag is on origin. Nothing blocks the
release itself.

## Priority 1 — pairing-e2e CI is RED (real regression, top priority)
CI fails on every push since the done-work landed. **Read
`backlog-pairing-e2e-room-id-divergence` for the full characterization.** Summary:
- The pi-host emits **divergent room IDs** — status room (`wc3B14rFnkrH`) ≠
  QR/pair-code room (`KzJ3MohnQOvq`), deterministic, within-host. Not a fluke:
  `e2e/run-pairing.sh` already runs `flutter test --concurrency=1` (serial) — an
  earlier "parallel-contamination" diagnosis was **wrong**; do not re-apply a
  `concurrency:1` "fix."
- **Reproduce locally:** `bash e2e/run-pairing.sh` (builds relay+pi-host+toxiproxy
  compose stack, then flutter test). Observed `+12 -4` + a 10s `TimeoutException`.
- **Lead:** `pi-extension/src/pairing/qr.ts:113` is the QR room sink
  (`params.set("rm", roomId)`). Find the status-side counterpart + the shared
  room derivation that diverges (room-keyed by `(cwd, name)`; suspects include
  the `to_room` sender-side room-targeting change and canonical-transcript-ordering).
- Regression window: green-capable at `0023ccd`, red from `56c5701` onward.
- Fix → verify `bash e2e/run-pairing.sh` green locally → push → CI green.

## Priority 2 — canonical-transcript-timestamp-ownership arc (IN FLIGHT, 5 implementing)
The biggest active work: `feature-canonical-transcript-timestamp-ownership` + 4
child stories (`ownership-foundation` → `extension-producer-ts` + `error-frame-ts`
→ `app-consume-cleanup`), all `stage: implementing`. This closes the **5-high gate
cluster** the v0.4.0 tiered gates independently rediscovered — the gate evidence
is captured in `backlog-timestamp-ownership-single-clock-gaps` (fold that in).
Establish one timestamp owner per tool event; carry producer timestamps on
`error`/`agent_done`/fallback narration; add a raw-JSON wire fixture through
`decodeServer`.

## Priority 3 — tiered-gate formalization eval
`idea-evaluate-tiered-release-gates`. The v0.4.0 tiered-gate trial **worked**
(caught 2 real regressions + real bugs/doc-drift more cheaply than the all-gates
default) but was **expensive** (~2.5M codex tokens, several scanners near the 2x
line). Decide whether to make it the default posture (full gates on non-`gate_origin`
code; security-only regression on `gate_origin` code) or keep ad hoc.

## Other active items (6 drafting — enumerate in `.work/active/`)
`epic-durable-transcript-ownership`, `feature-mobile-slash-command-invocation`,
`gate-security-combined-app-verification-flaky` (the one gate finding still
drafting — app verification flakiness), `story-canonical-transcript-ordering-systematic-ts-provenance-sweep`,
`story-mobile-extension-command-invocation`, `story-mobile-transcript-reorder-after-backlog-flush`.

## Backlog (v0.4.0 deferred findings — promote via `/agile-workflow:scope` when wanted)
`backlog-piext-windows-named-pipe-acl` · `backlog-ci-pin-deps-audit-e2e-pairing-refs`
· `backlog-new-session-teardown-session-shutdown` · `backlog-recoverable-delivery-resend-contract`
· `backlog-hot-reload-arm-path-behavioral-tests` · `backlog-herdr-script-hardening`
· `backlog-cockpit-v040-hardening` · `backlog-broker-audit-write-memory-ceiling`
· `backlog-v040-doc-drift-batch` · `backlog-protocol-codegen-dart-ir-from-schema`
· `backlog-hot-reload-cruft-batch` · `backlog-pattern-candidates-v040`.

## Hard-won lessons (don't repeat)
- **Diagnose test failures by reading the harness, not by symptom-pattern.** The
  pairing-e2e "flaky parallel contamination" call was wrong; one read of
  `run-pairing.sh` (`--concurrency=1`) corrected it.
- **`stage: done` is trustworthy but verify scope** against the finding's own
  remediation text (3 "done" gate findings were partial; 2 deliberate deferrals,
  1 genuine miss — the Windows IPC ACL).
- **Pre-rebrand tag landmine is now cleared** (`v0.4.0`/`v0.5.0`/`v0.6.0` deleted
  from origin); future cuts at those versions are safe.
