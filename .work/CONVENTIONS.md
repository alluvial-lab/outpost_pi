---
owner: workbench
schema: 1
workbench_version: 0.26.13
completed_items: summarize
review_weight: standard
simplification_posture: balanced
autonomy: adaptive
release_gates: [security, tests, cruft, docs, patterns, boundaries, lifecycle, protocol-contract]
validator_command: [python3, scripts/validate-work.py]
---

# Outpost-Pi Workbench Conventions

This `.work/` substrate tracks Outpost-Pi product and operational work across `pi-extension/`, `app/`, `relay/`, `site/`, and (when reactivated) `cockpit/`. Before designing, implementing, or reviewing, read `AGENTS.md` and `.agents/rules/*.md`. Durable foundations live in `docs/` (`VISION.md`, `SPEC.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `release-uat.md`, `site-deploy.md`) and `PROTOCOL.md`; detailed recurring implementation shapes live in `.agents/skills/patterns/`.

## Overbuilding calibration

- **Project context** — Single-operator, self-hosted, wire-paired 5-surface product (`pi-extension/`, `app/`, `relay/`, `site/`, plus dormant `cockpit/` frozen at Flutter 3.44.4). Security and reliable remote coding over untrusted networks matter; there are no external multi-tenant SaaS consumers or independent per-component downstream semver consumers.
- **Likely overbuilding shapes** — Premature multi-tenant abstractions, independent per-component semver/release machinery, speculative compatibility shims for unshipped surfaces, hand-mirrored wire DTOs where canonical schemas/generators exist, and unrequested work on dormant `cockpit/`.
- **Justified complexity** — End-to-end AEAD owner-channel security (`outer.ct`, signed ephemeral-DH pairing), explicit lifecycle ownership and teardown guards (Pi session replacement, WebSocket reconnect, Flutter `BuildContext` mounted guards, `working` state convergence), single-source-of-truth protocol contracts across TypeScript/Dart/Rust, bounded mailboxes/backpressure, and deterministic async/lifecycle regression tests.
- **Where cost is felt** — Mobile reconnect/rehydration latency and WebSocket frame sizes (relay outbound mailbox saturation on mobile links), Pi extension restart/reconnect turn-delivery latency, and relay memory per active room/peer. Numeric ceilings live in `PROTOCOL.md` and `relay/` resource policy.
- **Revisit evidence** — External multi-user distribution (such as Play Store launch), reactivation of `cockpit/`, or independent external consumers pinning a subproject.

## Verification commands

Run from the owning subproject root (see `.agents/rules/testing-integrity.md` for full guidance):

- `pi-extension/`: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
- `app/`: `flutter analyze && flutter test --exclude-tags e2e` (use `--concurrency=2` on constrained VMs)
- `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`
- `site/`: `pnpm lint && pnpm build`
- Cross-component E2E (repo root): `e2e/run-pairing.sh`
- `cockpit/`: dormant — excluded from release gates and normal scoping unless reactivated (CI keeps a compile+test guard on Flutter 3.44.4).

## Tags

Use existing component and concern tags for routing and filtering:

- `pi-extension` — Node/TypeScript Pi extension, daemon, mesh, pairing.
- `app` — Flutter mobile app.
- `relay` — Rust relay.
- `cockpit` — desktop cockpit (dormant unless reactivated).
- `site` — Next.js marketing/docs site.
- `workflow` — developer/operator workflow and CI.
- `research` — source-grounded discovery work informing implementation.
- `docs` — durable documentation, skills, or operator runbooks.
- `bug` — observed defect or regression.

## Research integration

`.research/` is an **alternate-owned ARD-style research substrate** (see `.research/CONVENTIONS.md`), not `workbench-research`. Preserve `.research/` and maintain it strictly through its own ARD conventions and `research-orchestrator` skill; do not run Workbench Research's linter, knowledge-index builder, or handoff against it.

When working an item tagged `research`, confirm and record the operator's ARD `research_dials` (`scope_authority`, `verification_rigor`, `intent`, `output_kind`) in item prose before dispatching research via `research-orchestrator`.

## Releases

- **Unified product versioning** — Outpost-Pi ships a single unified product version (`vX.Y.Z`) because `app/`, `relay/`, and `pi-extension/` are wire-paired and co-deployed. Components still deploy as independent artifacts (Docker image, APK, extension `dist/`, site image).
- **Two-lane slicing** — Fix lane (bugs/regressions in shipped surfaces) cuts patches (`v0.x.y`) as needed; feature lane cuts minors (`v0.x.0`) when a coherent batch is ready. Publishing, tagging, and deployment are always operator-gated.
- **Selective `.work/completed/` binding** — Fix-lane patch releases selectively bind only their fix stubs from `.work/completed/`, leaving parked feature stubs intact until the next minor cut.
- **E2E battery** — Minor cuts (`v0.x.0`) require the full E2E battery (`e2e/run-pairing.sh`, live lanes, and 600s seeded chaos soak `live_soak.py`) green before publish; patch cuts (`v0.x.y`) run `e2e/run-pairing.sh` plus lanes covering the changed surface.
- **Manual UAT checkpoint** — Before cutting a release tag, the operator runs and acknowledges the live smoke runbook in `docs/release-uat.md`.
- **Dormant exclusion** — `cockpit/` is excluded from release gates and release summaries while dormant.

## Release gates

Critical and high findings block release readiness until resolved; medium and low findings park to `.work/backlog/` (an operator may still promote a specific finding to blocking). Project-local scan lenses under `.agents/skills/scan-*/` supply the evidence contracts for `boundaries`, `docs`, `lifecycle`, and `protocol-contract`.

### security
Authentication, pairing/AEAD owner-channel boundaries, relay authorization, secret/key isolation, privacy of diagnostic logs, and supply-chain/dependency exposure must have no unresolved critical or high vulnerabilities across the release bundle.

### tests
Changed behavior and high-risk lifecycle/async/reconnect boundaries must be protected by deterministic, behavior-focused tests at stable interfaces (per `.agents/rules/testing-integrity.md`), with no gamed assertions or unattributed skips.

### cruft
Dead code, orphaned scaffolding, stale feature flags, redundant helpers, and obsolete workflow or comment residue introduced or exposed by the release bundle must be cleaned up before release.

### docs
Public docs, `PROTOCOL.md`, `CHANGELOG.md`, `AGENTS.md`, subproject guidance, and Always-tier native doc comments (checked via `.agents/skills/scan-documentation/`) must match shipped behavior with no dangling links or contradictory claims.

### patterns
Changed code must remain consistent with confirmed patterns in `.agents/skills/patterns/`, and any newly recurring pattern or stale anchor surfaced by the release bundle must be reconciled at the integration checkpoint.

### boundaries
Ports-and-adapters boundaries and fail-fast untrusted-input validation must hold across subprojects, checked via `.agents/skills/scan-boundaries/`.

### lifecycle
Long-lived resource teardown, Flutter `BuildContext` async guards, Pi stale-session handling, and `working` state convergence must hold on every exit path, checked via `.agents/skills/scan-lifecycle/`.

### protocol-contract
Wire message types, room/session metadata fields, and frame discriminators must derive from single-source schemas/registries without handwritten drift, checked via `.agents/skills/scan-protocol-contract/`.

## Review boundaries

Apply `standard` review weight by default. Prefer behavior-focused tests at stable interfaces where each test protects meaningful contract or regression risk. Park valuable out-of-scope findings into `.work/backlog/` with concrete evidence pointers rather than expanding active scope.

## Routing

- Keep Outpost-Pi code and operational work in this `.work/` ledger, separate from SNC root `.work/`.
- Local-only operational narratives and soak/drill logs belong in `.work/session-notes/` (gitignored; never commit). `scripts/validate-work.py` wraps Workbench's `--builtin` checks and permits `.work/session-notes/` only while it remains gitignored with zero tracked files.
