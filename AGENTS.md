# AGENTS.md — Outpost-Pi (public edition)

**Outpost-Pi** pairs a coding-agent harness with the machine it runs on:
drive your agents from your phone, keep ownership of the wire. Five
subprojects ship as independent artifacts — `pi-extension/`, `app/`, `relay/`,
`cockpit/`, `site/`.

> Local operators: the full deploy runbook and infra specifics live in
> `AGENTS.local.md` (gitignored). This file is what the public repo carries.

## Repository scope

- `origin` → `https://github.com/alluvial-lab/outpost_pi.git` — the only push target.
- Provenance: Outpost-Pi is derived from Jacob Moura's `remote_pi`
  (MIT-licensed); LICENSE and NOTICE preserve that attribution as a factual
  license matter. History is truncated at the import point — see NOTICE.

## Cockpit dormancy (operator decision 2026-08-27)

`cockpit/` is **dormant — freeze-with-guard posture**. The operator does not
use the cockpit or macOS (workstation is Arch Linux); revival happens when
the operator wants it (the `linux/` target is the intended revival surface).
Rules while dormant:

- CI keeps a compile+test guard on the frozen Flutter pin (3.44.4) — its job
  is to surface contract drift (cockpit-control.schema / extension changes),
  not to gate releases.
- No stack-currency migrations apply (no Flutter upgrades, no dependency
  refreshes, no platform-floor bumps). The freeze version is 3.44.4 = the
  v0.9.0-tested state.
- `cockpit-release` workflow stays disabled; no cockpit artifacts ship.
- Release gates, drains, and scoping exclude cockpit unless the operator
  reactivates it. Parked cockpit backlog items are dormant by extension.
- Revival checklist: re-verify against current trunk contracts (control RPC,
  theme tokens), un-freeze the Flutter pin via a normal stack-currency pass,
  re-enable the release workflow.

<!-- workbench:start -->
## Workbench

This repository is Workbench-owned. For stateful work, read
`.work/CONVENTIONS.md`, relevant foundations, and the selected skill. Follow
required references when their conditions apply; reuse unchanged context.
Never run setup without explicit user direction. Keep unrelated requests outside
Workbench; loose designs and reviews use project calibration without ledger mechanics.

Use `work` to own a continuous outcome, drawing on `design` for consequential
choices and `deliver` for ready implementation. Use `ideate` for early exploration,
`scan` for opportunities without remediation, `park` for selected findings, and
`release` only for a requested versioned summary.

The user's request and effective autonomy define scope. Ask about consequential
requirements; do not invent them or treat repository aspirations as current work.
Use features by default and `work/references/lifecycle.md` for hierarchy and cleanup.
Keep independent items parallel; `blocked_by` needs a real dependency.
Agents maintain `.work/`: reconcile encountered stale records and close verified
finished work in the same run, without separate housekeeping approval. Preserve
unmet requirements and live ownership; commit never-recorded items atomically
before completion or trimming, then apply configured retention.

Before any design or review, apply the current `## Overbuilding calibration` from
conventions. Pass it explicitly to delegated roles. The work item carries the
contract: designers author and revise it; implementers read it directly; the
outcome owner adjudicates scope and acceptance. Reviewers propose, not decide.

`.work/` holds operational state. Foundations hold durable repository or sub-project
truth, not delivery history. Write only durable artifacts named by the workflow;
keep questions, proposals, progress, and reports in chat. Preserve user-owned
roadmaps rather than rewriting them incidentally.

Reference work by name. Items, epics, and delivery units take domain-native
names — game mechanics, engine or framework vocabulary, not generic labels.
A number or letter code never stands alone in user-facing communication
(conversation, reports, commit messages): pair it with its name. Include the
context a reader needs when the transcript does not already carry it. Machine
fields and dense intra-item tables keep bare identifiers.

For all repository writes, including loose edits, commit owned changes before
handoff or the final report. Reviews use committed targets; follow the minimum
Git floor in `work/references/git-posture.md`. Read-only work needs no empty commit.

Apply configured execution, review, simplification, and commit postures; unset
execution means `inline-first` under `work/references/sub-agents.md`.
Align optional design review once per run and choose coherent implementation checkpoints.
Use `work/references/review.md` for concrete Workbench reviews. Verify each unit
promptly; keep pending review visible until acceptance. Before closure, reconcile
affected foundations and indexes and complete the lifecycle sweep. Use another
context when it adds enough value or is requested; do not restart settled work.
Park valuable adjacent findings instead of silently adding them to scope.
<!-- workbench:end -->

## Work tracking

This repo carries its own Workbench `.work/` ledger for Outpost-Pi code/product
bugs, features, stories, and operational work:

- `.work/CONVENTIONS.md` — Workbench conventions, overbuilding calibration, verification commands, tags, and release gates.
- `.work/active/` — active epics, features, and stories (flat files).
- `.work/backlog/` — parked bugs, ideas, and deferred work.
- `.work/completed/` — completion stubs for finished items awaiting release.
- `.work/releases/` — flat release summaries.

`.work/session-notes/` is gitignored local-only territory (never commit).

## Agent operating discipline

Before designing, implementing, or reviewing, read the agent-neutral rules in `.agents/rules/`:

- `.agents/rules/agent-discipline.md` — startup checklist, cwd/subproject boundaries, provenance, durable-vs-transient artifacts.
- `.agents/rules/code-design.md` — ports/adapters, single source of truth, generated/inferred contracts, fail-fast boundaries, lifecycle ownership.
- `.agents/rules/documentation-discipline.md` — current-state docs, inline self-defense, link/reference hygiene, README audience.
- `.agents/rules/testing-integrity.md` — no gaming tests, failure triage, subproject verification commands.

## Existing project guidance

Read `CLAUDE.md` at the repo root for orchestration/planning posture, and the subproject `CLAUDE.md` before editing that subproject (`pi-extension/`, `app/`, `relay/`, `cockpit/`, `site/`). These files are harness-neutral reference docs, not Claude-exclusive.

## Agent reference surface

`.agents/skills/<reference>/SKILL.md` carries current language/library/dev-cycle guidance; load the relevant one before touching code:

- `code-design-principles`, `documentation-conventions`
- `pi-extension-typescript`, `flutter-mobile`, `rust-relay`, `flutter-desktop-cockpit`, `next-site`
- `mobile-remote-coding` (cross-cutting reconnect/state-machine checklist)

Until the rest are authored, subproject `CLAUDE.md` files plus `PROTOCOL.md` are the minimum required context.

## Common commands

Run from the owning subproject root.

```bash
# pi-extension/
corepack pnpm typecheck && corepack pnpm test && corepack pnpm build

# app/
flutter analyze
flutter test --exclude-tags e2e

# cross-component E2E (repo root)
e2e/run-pairing.sh

# relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test

# cockpit/
flutter analyze && flutter test

# site/
pnpm lint && pnpm build
```

On memory-constrained machines, cap the Android Gradle heap
(`org.gradle.jvmargs=-Xmx3G`, temp dir off tmpfs) before building the APK;
debug builds are the deploy target.

## Paired wire changes (deploy together)

Version-paired changes that break across mixed versions:

- **Auth domain-separation** (`app ↔ relay`, v0.1.0): app signs
  `outpost-pi-relay-auth-v1\n` ++ nonce; relay verifies the same. Hard cutover.
- **`to_room` required** (`relay ↔ extension`, v0.1.0): relay rejects
  `pi_envelope` frames with empty `to_room` as `bad_envelope`. Cross-PC mesh
  only; app↔pi path unaffected.
- **Cockpit control-RPC discriminator** (`extension ↔ cockpit`, v0.1.0):
  NUL-prefixed control string `\x00outpost-pi-ctrl:`, structured type
  `outpost_pi_control`. Hard cutover.
- **Owner-channel E2E** (`app ↔ extension`, target v0.3.0): signed ephemeral-DH
  pairing (`pair_request`/`pair_ok`; raw pair token never crosses the wire),
  sealed `outer.ct` frames post-pairing, AEAD as the security boundary.
  Re-pairing is the recovery path for key loss. Relay untouched (`ct` stays
  opaque).
- **Recoverable owner delivery** (`app ↔ extension`, deploy together): the app
  persists each unconfirmed `user_message` before channel send; an extension
  restart fence returns `delivery_retry` without SDK delivery, and the app
  retries the original id only after fresh room/session confirmation. This is
  durable at-least-once recovery, not exactly-once delivery. Relay untouched.
- **Verified Android pairing links** (`extension ↔ app ↔ site`, v0.9.0): the
  extension emits `https://outpost-pi.kevoun.com/pair#…`; the Android app
  accepts that exact origin/path through an `autoVerify` App Link, and the site
  serves `/.well-known/assetlinks.json` for package `dev.kevoun.outpostpi` and
  the release signing certificate. The enrollment fields stay in the fragment,
  so browser fallback requests do not disclose them to the site. Deploy the
  site association before the paired extension/app release.
- **Storage/keyring/launchd identifiers** (v0.1.0, destructive): Hive boxes
  `dev.outpostpi.*`, keyring `dev.outpostpi.pi`, launchd `dev.outpostpi.supervisord`,
  env `OUTPOST_PI_*`/`OUTPOSTPI_*`. Old-label daemon cleanup:
  `launchctl bootout gui/$(id -u)/dev.remotepi.supervisord`.

Safe deploy order: **relay → full Pi restart → app sideload → cockpit**.

### Reload vs restart (pi-extension)

`/reload` in the pi TUI does **not** re-import `dist/` for a `type: module`
(ESM) extension — Node's ESM cache is immutable at runtime. A source edit is
only picked up by a full pi process restart. See
`pi-extension/docs/daemon.md` for the hot-reload/restart-wrapper mechanics
(`scripts/pi-restart-loop.sh`, `scripts/hot-reload.sh`, agent_settled-gated).

## Brand

Identity v2.0 — **Phosphor Beacon** (dark `#0D1210` / light `#F3F6F3`,
accent `#74CC9C`/`#256E47`), **Constellation III** mark, **Space Mono**
across product surfaces; the generated banner PNG uses the approved Noto Sans
Mono fallback on the build VM. Contract: `.mockups/design-system/tokens.css`; canonical mark geometry in
`branding/logo-foreground.svg` with validated SVG projections in `branding/`;
regeneration: `scripts/generate-brand-assets.py` (Pillow — no external SVG
converter needed). Do not commit generated `dist/`, build
artifacts, or secrets.
