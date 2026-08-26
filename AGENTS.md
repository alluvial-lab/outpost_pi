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

## Work tracking

This repo carries its own `.work/` queue for Outpost-Pi code/product bugs,
follow-up slices, and operational work.

- `.work/backlog/` — parked bugs and ideas.
- `.work/active/stories/` — scoped implementation-sized work.
- `.work/active/features/` — multi-story or design-bearing work.
- `.work/active/epics/` — larger arcs.
- `.work/CONVENTIONS.md` — frontmatter, tags, and routing rules.

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
- **Storage/keyring/launchd identifiers** (v0.1.0, destructive): Hive boxes
  `dev.outpostpi.*`, keyring `dev.outpostpi.pi`, launchd `dev.outpostpi.supervisord`,
  QR scheme `outpostpi://`, env `OUTPOST_PI_*`/`OUTPOSTPI_*`. Old-label daemon
  cleanup: `launchctl bootout gui/$(id -u)/dev.remotepi.supervisord`.

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
Mono fallback on the build VM. Contract: `.mockups/design-system/tokens.css`; canonical SVGs in
`branding/`; regeneration: `scripts/generate-brand-assets.py` (Pillow — no
external SVG converter needed). Do not commit generated `dist/`, build
artifacts, or secrets.
