# AGENTS.md — Remote Pi private fork (hard fork, rebrand pending to Outpost-Pi)

This checkout is a **hard fork** of `jacobaraujo7/remote_pi`, fully owned by the
operator. It has diverged past the point of upstream rebase (547 commits ahead,
0 upstream since the fork point as of 2026-07-02); the rebrand to **Outpost-Pi**
is tracked in `epic-rebrand-to-outpost-pi`. Treat the fork as the product, not
a set of patches awaiting upstream.

## Repository posture

- Design **fork-local by default**: fixes and features live in code we control
  (`pi-extension/`, `app/`, `relay/`, `cockpit/`, `site/`) and ship by
  rebuilding our own artifacts. Do not gate decisions on upstream absorbability.
- Fork remote: `origin` → `https://github.com/KevounC/remote_pi.git` — the only
  push target.
- Upstream remote: `upstream` → `https://github.com/jacobaraujo7/remote_pi.git`
  with push disabled — historical provenance and read-only comparison only,
  not a design constraint.
- Push to `origin` unless the operator explicitly asks for an upstream PR.

## Work tracking

This fork has its own `.work/` queue. Use it for Remote Pi code/product bugs, follow-up slices, and fork-owned operational work.

- `.work/backlog/` — parked bugs and ideas.
- `.work/active/stories/` — scoped implementation-sized work.
- `.work/active/features/` — multi-story or design-bearing work.
- `.work/active/epics/` — larger arcs.
- `.work/CONVENTIONS.md` — frontmatter, tags, and routing rules.

Do **not** park Remote Pi code/product bugs in the SNC root `.work/` queue. SNC root can record high-level operator context, but concrete Remote Pi implementation work belongs here.

## Agent operating discipline

Before designing, implementing, or reviewing, read the agent-neutral rules in `.agents/rules/`:

- `.agents/rules/agent-discipline.md` — startup checklist, cwd/subproject boundaries, fork posture, durable-vs-transient artifacts.
- `.agents/rules/code-design.md` — ports/adapters, single source of truth, generated/inferred contracts, fail-fast boundaries, lifecycle ownership.
- `.agents/rules/documentation-discipline.md` — current-state docs, inline self-defense, link/reference hygiene, README audience.
- `.agents/rules/testing-integrity.md` — no gaming tests, failure triage, subproject verification commands.

These files are harness-neutral. If Pi's agile-workflow extension auto-loads `.agents/rules/`, still read the relevant rule body directly when a task depends on it.

## Existing project guidance

Read `CLAUDE.md` at the repo root for the orchestration/planning posture, and read the subproject `CLAUDE.md` before editing that subproject:

- `pi-extension/CLAUDE.md` — Node/TypeScript Pi extension.
- `app/CLAUDE.md` — Flutter mobile app.
- `relay/CLAUDE.md` — Rust relay.
- `cockpit/CLAUDE.md` — Flutter desktop cockpit.
- `site/CLAUDE.md` — site.

`CLAUDE.md` files are not Claude-exclusive when they describe project behavior; treat them as local reference docs. Root is primarily planning/orchestration. Code edits normally belong in the relevant subproject.

## Agent reference surface

Remote Pi is adopting platform-style agent references so implementation/review agents have current language, library, and development-cycle guidance before touching code. The pattern and template live at `docs/agent-reference-surface.md`. New canonical references should prefer `.agents/skills/<reference>/SKILL.md` so Pi/Codex/non-Claude agents can read them directly; Claude-facing files may link to those references but should not become the only source of API facts.

When picking up any active `.work` item tagged `research` or containing `research_dials`, load and follow the `research-orchestrator` skill before authoring research-backed docs, skills, briefs, or references. Treat the item's `research_dials` as the commissioning registration and surface/confirm them through that workflow rather than proceeding ad hoc.

First-wave references are tracked in `.work/active/features/feature-agent-reference-surface.md` and children. Available references:

- `.agents/skills/code-design-principles/SKILL.md` — generic design/implementation principles adapted from SNC/platform: ports/adapters, single source of truth, generated contracts, fail fast, lifecycle ownership, convergent state.
- `.agents/skills/pi-extension-typescript/SKILL.md` — `pi-extension/` TypeScript/Pi SDK lifecycle work.
- `.agents/skills/flutter-mobile/SKILL.md` — `app/` Flutter mobile lifecycle, provider/ViewModels, routing, WebSocket reconnect, and room/session state.
- `.agents/skills/rust-relay/SKILL.md` — `relay/` Rust async WebSocket routing, mesh membership, presence/rooms, logging/privacy, and relay tests.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — `cockpit/` Flutter desktop lifecycle, shadcn/modular/Hive patterns, terminal/PTY, file/window/native plugin surfaces, and cockpit tests.
- `.agents/skills/next-site/SKILL.md` — `site/` Next App Router, React Server/Client Components, Tailwind 4/PostCSS, standalone Docker deploy, and site lint/build workflow.
- `.agents/skills/mobile-remote-coding/SKILL.md` — cross-cutting mobile remote-coding state-machine and reconnect checklist for app/extension/relay work.

Until the rest are authored, agents should treat subproject `CLAUDE.md` files plus `PROTOCOL.md` as the minimum required context. Prefer adding future reusable references under `.agents/skills/`; use `.claude/skills/` only as a compatibility mirror or pointer, not as the canonical source of generic API/design facts.

## Common commands

Run commands from the owning subproject root.

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

From `app/`:

```bash
flutter analyze
flutter test
```

From `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

From `cockpit/`:

```bash
flutter analyze
flutter test
```

From `site/`:

```bash
pnpm lint
pnpm build
```

Do not commit generated `dist/`, build artifacts, local `.pi/`, or secrets.

## Deployment and running

This fork runs end-to-end on the dev VM (`codebox` = `<lan-ip>`). The
three runtime components are **separate artifacts** that deploy independently,
and the pi-extension is registered as a **local-path** extension (not npm).

### Component locations and how they load

- **relay** — Docker container `remote-pi-relay` on `:3300` (host) → `:3000`
  (container). Image built from `relay/` source (`docker build -t
  remote-pi-relay:<version> relay/`); the persistent `mesh_versions` SQLite DB
  lives in the named volume `remote-pi-data:/data`. Do NOT confuse with the
  upstream image `jacobmoura7/remote-pi-relay:latest` (stale). The live
  container runs `remote-pi-relay:0.2.2` with the retroactive file log
  enabled: `REMOTEPI_RELAY_LOG_DIR=/data/logs` (daily-rotated `relay.log`
  in the volume) + `RUST_LOG=info,relay=debug` (lifts the cross-PC
  `pi_envelope` forward-path `debug!` carrying `env_id_tail` — the
  cross-side correlation key that joins the phone's `msg-send id` and the
  extension's `app user_message id`).
- **pi-extension** — registered in `~/.pi/agent/settings.json` as the local path
  `/home/agent/projects/remote_pi/pi-extension`, loading `dist/index.js` (the
  `package.json` `main`). npm publishes `0.5.3`; ignore — the local path is
  authoritative. `dist/` is gitignored and **not rebuilt automatically**; a
  source edit requires `corepack pnpm build` (or `./node_modules/.bin/tsc` to
  bypass the corepack deps-status RO-cache check) before it's live.
  **Delivery-path debug log:** set `REMOTE_PI_DEBUG_LOG=1` in the pi
  process's environment to enable a bounded ring + file at
  `~/.pi/remote/debug/delivery.log` capturing the `messageApi`/`commandCtx`
  lifecycle, `wakeAgent` outcomes, the replay queue, and `session_start`/
  `session_shutdown` reasons — all keyed by the message `id` that joins the
  phone's `msg-send` and the relay's `env_id_tail`. Default off (no-op). Needs
  a full pi restart to take effect (not `/reload`).
- **app** — Flutter mobile; sideloaded via `adb install <apk>` to a phone on a
  workstation (the VM has no phone attached).

### Paired wire changes (deploy together)

relay-0.2.0 introduced two wire changes that are **version-paired** — mixed
versions break:
- **Auth domain-separation** (`app-v1.2.0` ↔ `relay-0.2.0`): app signs
  `remote-pi-relay-auth-v1\n` ++ nonce; relay verifies the same. Old app +
  new relay (or vice versa) fails the WS handshake.
- **`to_room` required** (`relay-0.2.0` ↔ `extension-0.6.0` sender): the
  relay rejects `pi_envelope` frames with empty/missing `to_room` as
  `bad_envelope`. The sender-side room-targeting (targeting the sibling's
  actual room, not the temporary `"main"` default) is deferred to design —
  see `story-to-room-sender-side-room-targeting`. It only affects **cross-PC
  agent mesh** (Pi↔Pi `agent_send`); the app↔pi path is unaffected.

Safe deploy order: **relay first**, then reload/restart the extension, then
sideload the app.

### Reload vs restart (pi-extension)

`/reload` in the pi TUI re-fires `session_start` against the **already-loaded**
module instance — it does **not** re-import `dist/index.js`. A source edit is
only picked up by a **full pi process restart** (quit + relaunch), not
`/reload`. If a fix is in `dist/` but the symptom persists after `/reload`, a
stale module is still in memory; restart pi.

This was verified empirically (2026-07-07): instrumentation fields added to
`dist/transport/peer_channel.js` (commit `01006f9`, built 15:17) were absent
from a capture taken immediately after `/reload`, while earlier fields (commit
`9a15503`, built 13:35, loaded by the prior full restart) were present. So the
running process kept the stale module despite `/reload`. A static trace of
`agent-session.reload()` → `resourceLoader.reload()` → `clearExtensionCache()`
→ `jiti.import` suggested re-import SHOULD occur, but the harness's `/reload`
does not re-import the extension module in practice (the in-memory
`extensionCache` factory is retained, or the harness `/reload` does not invoke
the full `agent-session.reload()` path). Trust the empirical result, not the
trace: **full restart to load a `dist/` change**.

### Relay container commands

```bash
# build from current fork source
docker build -t remote-pi-relay:0.2.2 relay/
# run (reproduces the live container's config: port 3300→3000, named volume,
# retroactive file log + cross-side debug correlation)
docker run -d --name remote-pi-relay -p 3300:3000 \
  -v remote-pi-data:/data \
  -e REMOTEPI_RELAY_PORT=3000 \
  -e REMOTEPI_MESH_DB_PATH=/data/mesh.db \
  -e REMOTEPI_RELAY_LOG_DIR=/data/logs \
  -e RUST_LOG="info,relay=debug" \
  --restart unless-stopped remote-pi-relay:0.2.2
# rebuild from updated source + swap in
docker stop remote-pi-relay && docker rm remote-pi-relay  # then build + run
# read the persistent relay log (survives scroll/restart; daily-rotated)
docker exec remote-pi-relay tail -f /data/logs/relay.log.$(date -u +%F)
```

Without `REMOTEPI_RELAY_LOG_DIR`, logging is stdout-only (lost on
scroll/restart — the pre-0.2.2 gap). `RUST_LOG` defaults to `info`; the
`relay=debug` lift is what surfaces the `env_id_tail` correlation line on
each cross-PC forward/drop (the app↔pi data-plane path stays
payload-opaque at INFO with `warn!` on drops). Rotated `relay.log.YYYY-MM-DD`
files older than 14 days are pruned on startup (`prune_old_relay_logs`) —
`tracing-appender` rotates but does not retain, so without the sweep one
file per day would accumulate without limit in the named volume.

### App APK build on the dev VM (memory-sensitive)

The VM has 11G RAM shared with ~10 other containers. The default
`android/gradle.properties` heap (`-Xmx8G`) is for a workstation and will **OOM
the VM**; `/tmp` is a **tmpfs** (RAM-backed) that Gradle also uses for build
  temp. Two fixes are required for a safe build on the VM:
- cap the Gradle heap to `3G` and redirect its temp off tmpfs:
  `org.gradle.jvmargs=-Xmx3G ... -Djava.io.tmpdir=/home/agent/.gradle-tmp`
  (mkdir `/home/agent/.gradle-tmp` first; it's on the 54G disk)
- prefer `flutter build apk --release` (single fat APK, one dart2native pass)
  over `--split-per-abi` (3 passes, ~3× peak RAM) when RAM is tight

Toolchain: Flutter at `~/projects/remote_pi/.tools/flutter`, JDK 21
(`JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`), Android SDK API 36 at
`/opt/android-sdk`. Full build-path notes in `.agents/skills/flutter-mobile/SKILL.md`.

### Sideload to phone

The phone is attached to a workstation, not the VM. After building on the VM,
copy the APK to the workstation and install with `adb` (USB debugging on):
```bash
scp app/build/app/outputs/flutter-apk/app-release.apk <workstation>:~/app.apk
# on the workstation:
adb install -r ~/app.apk   # -r keeps data; INSTALL_FAILED_UPDATE_INCOMPATIBLE →
                            # adb uninstall dev.remotepi.app && adb install
```
The app's `pubspec.yaml` version is NOT bumped by `release-deploy`; bump it
manually before building when shipping a new version.
