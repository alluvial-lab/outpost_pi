# Outpost-Pi work conventions

This `.work/` tier tracks Outpost-Pi product and ops work.
Use it for bugs, follow-up slices, and product/ops ideas that belong with the codebase rather than in the SNC root queue.

Before advancing work items, read `AGENTS.md` and `.agents/rules/*.md`. The rule surface is agent-neutral; `.work/` is the queue, not the place to preserve lasting design/routing policy.

## Layout

- `backlog/` — parked bugs and ideas, flat files.
- `active/stories/` — scoped implementation-sized work.
- `active/features/` — multi-story or design-bearing work.
- `active/epics/` — larger arcs that decompose into features/stories.
- `archive/` — completed/retired items when they no longer need active bodies.

## Frontmatter

Backlog items use:

```yaml
---
id: <slug>
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [<tag>, ...]
---
```

Active items use:

```yaml
---
id: <kind>-<slug>
kind: epic|feature|story
stage: drafting|implementing|review|done
tags: [<tag>, ...]
parent: <id>|null
depends_on: [<id>, ...]
release_binding: <version>|null
gate_origin: <gate-name>|null
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

For normal user-scoped items, set `release_binding: null` until `release-deploy` binds the item to a release, and set `gate_origin: null` unless the item was produced by a release gate.

Research-tagged active items additionally carry an ARD-style registration block:

```yaml
research_dials:
  scope_authority: pre-registered|mixed|in-engagement-judgment
  verification_rigor: floor|standard|full
  intent: <short free-text inventory value>
  output_kind: <short free-text inventory value>
```

The operator-confirmed dials are part of scoping. If a research item lacks them, pause before dispatching research and confirm/register dials instead of silently proceeding.

When picking up any active item tagged `research` or containing `research_dials`, load and follow the `research-orchestrator` skill before authoring research outputs. Do not produce research-backed docs, skills, briefs, or references ad hoc; the item's `research_dials` are the commissioning registration and must be surfaced/confirmed according to the orchestrator workflow.

## Tags

Start small. Current tags:

- `pi-extension` — Node/TypeScript Pi extension work.
- `app` — Flutter mobile app work.
- `relay` — Rust relay work.
- `cockpit` — desktop cockpit work.
- `workflow` — developer/operator workflow for the fork.
- `research` — source-grounded discovery work whose output informs later implementation.
- `docs` — agent/reference documentation, skills, or operator docs.
- `bug` — observed defect or regression.

## Releases

This fork ships a **single unified product version** (`vX.Y.Z`) covering the
whole Outpost-Pi product. All items bind to the one product release regardless
of which component they touch. Components still deploy as independent artifacts
(docker image, APK, extension `dist/`, desktop install) and may carry their own
artifact identifiers (`outpost-pi-relay:0.4`, app `versionName`), but those are
deploy details recorded in the release — not separate substrate releases.

The fork reset to `0.1.0` at the Outpost-Pi rebrand (`release-v0.1.0`,
2026-07-12). Earlier pre-rebrand tags (`app-v1.x`, `cockpit-v1.x`,
`extension-0.5.x`, `relay-0.1.0`, `v0.4.0`/`v0.5.0`/`v0.6.0`) were deleted; the
retained item bodies for those old generations were relocated to
`.work/releases-pre-rebrand/` as historical record.

**Why unified (changed 2026-08-11).** Per-component semver was inherited
convention, but this is a single-operator product whose components are
wire-paired (app↔relay↔extension↔cockpit cut together) and co-deployed — they
move in lockstep, so independent component versions were ceremony without
independence. Cross-cutting work forced a repo-level release *alongside*
component cuts, and the operator ended up cutting both `vX.Y.Z` and
`app-vX.Y.Z`/`cockpit-vX.Y.Z` for the same batch. Unified versioning collapses
that to one release event. Component tags are retained on items for
routing/scan purposes but no longer split the release. Per-component semver
would regain its value only if components gained independent external consumers
pinning each one. (Historical per-component releases under `.work/releases/` —
`app-v0.2.0`/`v0.3.0`, `cockpit-v0.2.0`/`v0.3.0`, `extension-0.2.0`,
`relay-0.2.0` — remain as record.)

**Why the pre-rebrand relocation.** work-view resolves `--release <version>`
by scanning `.work/`, `.work/active/`, `.work/archive/`, and `.work/releases/`
(recursively) for matching `release_binding:` frontmatter values. Pre-rebrand
versions share exact version numbers with the post-rebrand series, so any
retained item still carrying a pre-rebrand binding value would be silently
swept into a future release's gate scope + readiness check at the version
collision — a landmine far from cause. Moving them out of the scanned tiers
(`.work/releases-pre-rebrand/` is a top-level sibling, invisible to
work-view) removes the whole collision class. Do not move pre-rebrand
release artifacts back into `.work/releases/` or `.work/archive/`.

### Attribution rule (unified)

All items bind to the single product release `vX.Y.Z` regardless of component
tags. `release-deploy <version>` is invoked once per product version.
Component tags on items are retained for routing/scan filtering but no longer
split items across component releases.

### Release config

- `release_slicing: two-lane (fix/feature)` — operator policy (2026-08-25):
  work items stay unbound; each `release-deploy` binds selectively.
  Fix lane (bugs/regressions in shipped surfaces) → patch cuts `v0.8.x`,
  cut whenever needed. Feature lane (parked queue) → minor cuts `v0.9.0+`,
  cut when a coherent batch is done. App `+versionCode` is a dev counter
  that increments freely on trunk; the release tag is chosen at cut time
  from the bind set. Every cut runs the rc flow (`v<ver>-rc.<n>` draft
  prerelease → operator UAT → publish promotes fat + slim-arm64 artifacts);
  publishing is always operator-gated per release, trunk is never blocked
  on a prior release's UAT.
- `release_mapping: tag-based` — git tags mark releases; push is external
  (operator runs from their machine). `release-deploy` creates the tag locally;
  the operator pushes.
- `gates_for_release: [security, tests, cruft, docs, patterns, refactor]` — bold-refactor
  work is shipped and the substrate is gate-capable (work-view 0.15.3 installed). The
  `refactor` gate is now active: three Remote-Pi-native scan-rule libraries are installed
  under `.agents/skills/scan-{boundaries,lifecycle,protocol-contract}/` (all untagged,
  `findings-route: none` — findings route through story/feature design, not
  refactor-design, because the fixes are not black-box-preserving). The libraries are
  grounded in `.agents/rules/code-design.md` and were cross-model-reviewed before commit.
  Tiered-gate model (v0.4.0 trial: full gates on feature items, security-only regression
  on gate-origin items) evaluated 2026-08-26 and **not carried forward** — post-trial
  releases ran all six gates by default, and proportionality is handled by two-lane
  release slicing; record at `.work/archive/idea-evaluate-tiered-release-gates.md`.
- `release_uat: manual-checkpoint` — after the automated `gates_for_release` pass and
  before tag creation, `release-deploy` pauses for operator action; the operator runs
  the smoke runbook in [`docs/release-uat.md`](../docs/release-uat.md) and records an
  ack before the tag is cut. This is **not** a `gates_for_release` slot: `release-deploy`
  invokes each of those as `Skill(skill="agile-workflow:gate-<name>")`, and there is no
  `gate-uat` skill, so a `uat` entry there would fail to resolve and halt the release.
  The manual-checkpoint path uses `release-deploy`'s built-in "mapping requires user
  action → pause and prompt" pause instead. The durable automation that catches
  integration regressions going forward is `feature-cross-component-e2e-pairing-suite`;
  this runbook is the independent, sooner backstop (motivating incident: `v0.6.0`
  non-functional ship).
- `gate_finding_routing: { critical: implementing, high: implementing, medium: backlog, low: backlog }`
  — gate findings are routed by severity into blocking vs trackable work. **critical/high
  are release-blocking**: they bind to the release and ship blocks on them reaching `done`.
  **medium/low are non-blocking**: they are unbound from the release (`release_binding: null`)
  and land in `.work/backlog/` as tracked improvements, so the release ships once its
  blocking findings resolve. This is the fork's deliberate posture: the gate surfaces real
  issues without low/medium findings stalling every ship. (An operator may still mark a
  medium/low finding blocking case-by-case by leaving it bound — e.g., a debug artifact left
  in production is worth fixing before ship regardless of nominal severity.)
- `terminal-tier retention: retain-bodies` — bound item bodies stay on disk.
  Active done items move to `.work/releases/<version>/`; archived items stay in
  `.work/archive/`. A release summary doc is produced at
  `.work/releases/<version>/release-<version>.md`.
- `binding_guard: warn` (default) — cross-component work legitimately spans
  releases; INCOMPLETEs under `epic_cohesion: phased` (default) are informational.

## Routing

### Archive-tier semantics (added 2026-07-24)

`.work/archive/` holds two classes: **done items** awaiting release
late-binding, and **retired husks** — merge-absorbed, duplicate, superseded,
or resolved-in-substance items whose substance lives elsewhere. Rules:

- Retired husks MUST carry `status: superseded|duplicate` plus a pointer
  (`superseded_by:` / `folded_into:` / `duplicate_of:`) at retirement time.
  The release-deploy archived-stub gather skips status-stamped and non-`done`
  archive files (patched 2026-07-24 after the same stale-stub sweep hit both
  v0.2.0 and v0.3.0).
- Grooms that merge/absorb items MUST stamp the absorbed files as part of the
  merge commit (the 2026-07-22 groom merged 15 findings into 3 backlog items
  without stamping; release-deploy re-swept the husks twice).
- Genuinely incomplete work belongs in `.work/backlog/`, not `.work/archive/`.
  An archived item at `stage: drafting|implementing` is a smell — either stamp
  it as retired or move it back to backlog.

## Routing

- Keep code-owned Remote Pi bugs here.
- Keep SNC root `.work/` for SNC operational orchestration only.
- Keep `plan/` for broader architectural plans already used by this repo; `.work/` is the queue for concrete bugs/slices.
- Upstream contribution remains opt-in. Private-carry work can live here without opening upstream PRs.
