# AGENTS.md — Outpost-Pi

**Outpost-Pi** is a multi-surface product owned and shipped by the operator.
The codebase spans five subprojects — `pi-extension/`, `app/`, `relay/`,
`cockpit/`, `site/`; design changes freely across all of them and ship by
rebuilding our own artifacts.

## Repository scope

- `origin` → `https://github.com/alluvial-lab/outpost_pi.git` — the only push
  target.
- Provenance: Outpost-Pi is derived from Jacob Moura's `remote_pi`
  (MIT-licensed); the LICENSE and NOTICE preserve that attribution as a
  factual license matter, not a design constraint.

## Work tracking

This fork has its own `.work/` queue. Use it for Outpost-Pi code/product bugs, follow-up slices, and fork-owned operational work.

- `.work/backlog/` — parked bugs and ideas.
- `.work/active/stories/` — scoped implementation-sized work.
- `.work/active/features/` — multi-story or design-bearing work.
- `.work/active/epics/` — larger arcs.
- `.work/CONVENTIONS.md` — frontmatter, tags, and routing rules.

Do **not** park Outpost-Pi code/product bugs in the SNC root `.work/` queue. SNC root can record high-level operator context, but concrete Outpost-Pi implementation work belongs here.

## Agent operating discipline

Before designing, implementing, or reviewing, read the agent-neutral rules in `.agents/rules/`:

- `.agents/rules/agent-discipline.md` — startup checklist, cwd/subproject boundaries, provenance, durable-vs-transient artifacts.
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

Outpost-Pi is adopting platform-style agent references so implementation/review agents have current language, library, and development-cycle guidance before touching code. The pattern and template live at `docs/agent-reference-surface.md`. New canonical references should prefer `.agents/skills/<reference>/SKILL.md` so Pi/Codex/non-Claude agents can read them directly; Claude-facing files may link to those references but should not become the only source of API facts.

When picking up any active `.work` item tagged `research` or containing `research_dials`, load and follow the `research-orchestrator` skill before authoring research-backed docs, skills, briefs, or references. Treat the item's `research_dials` as the commissioning registration and surface/confirm them through that workflow rather than proceeding ad hoc.

First-wave references are tracked in `.work/active/features/feature-agent-reference-surface.md` and children. Available references:

- `.agents/skills/code-design-principles/SKILL.md` — generic design/implementation principles adapted from SNC/platform: ports/adapters, single source of truth, generated contracts, fail fast, lifecycle ownership, convergent state.
- `.agents/skills/documentation-conventions/SKILL.md` — the three-tier (Always/Recommended/Skip) native-doc intent model and agent-scan enforcement for TypeScript (JSDoc), Dart (dartdoc), and Rust (rustdoc).
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
flutter test --exclude-tags e2e
```

Run the dedicated cross-component E2E pairing harness from the repository root:

```bash
e2e/run-pairing.sh
```

On this VM, full-suite runs use `--concurrency=2` for load-sensitive timing tests.

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

This fork runs end-to-end on the dev VM (`dev-vm` = `<lan-host>`). The
three runtime components are **separate artifacts** that deploy independently,
and the pi-extension is registered as a **local-path** extension (not npm).

### Component locations and how they load

- **relay** — Docker container `outpost-pi-relay` on `:3300` (host) → `:3000`
  (container). Image built from `relay/` source (`docker build -t
  outpost-pi-relay:<version> relay/`); the persistent `mesh_versions` SQLite DB
  lives in the named volume `outpost-pi-data:/data`. The live
  container runs `outpost-pi-relay:0.1.0` with the retroactive file log
  enabled: `OUTPOSTPI_RELAY_LOG_DIR=/data/logs` (daily-rotated `relay.log`
  in the volume) + `RUST_LOG=info,relay=debug` (lifts the cross-PC
  `pi_envelope` forward-path `debug!` carrying `env_id_tail` — the
  correlation key for cross-PC relay envelopes only; app↔Pi owner-message IDs
  are inside sealed `outer.ct` and cannot be joined by the relay).
- **pi-extension** — registered in `~/.pi/agent/settings.json` as the local path
  `/home/agent/projects/outpost_pi/pi-extension`, loading `dist/index.js` (the
  `package.json` `main`). The local path is authoritative. `dist/` is gitignored
  and **not rebuilt automatically**; a source edit requires
  `corepack pnpm build` (or `./node_modules/.bin/tsc` to bypass the corepack
  deps-status RO-cache check) before it's live. **Note:** `corepack pnpm` in
  this sandbox needs `COREPACK_HOME=<writable dir>` + `--store-dir <writable
  store>` because `/home/agent/.local-state` is read-only.
  **Delivery-path debug log:** set `OUTPOST_PI_DEBUG_LOG=1` in the pi
  process's environment to enable a bounded ring + file at
  `~/.pi/remote/debug/delivery.log` capturing the `messageApi`/`commandCtx`
  lifecycle, `wakeAgent` outcomes, the replay queue, and `session_start`/
  `session_shutdown` reasons — keyed by the local owner message `id` for app↔extension tracing; sealed
  owner frames are not relay-correlated by `env_id_tail`. Default off (no-op). Needs
  a full pi restart to take effect (not `/reload`).
- **app** — Flutter mobile; sideloaded via `adb install <apk>` to a phone on a
  workstation (the VM has no phone attached).
- **tailscale** — docker container `tailscale` (tailscale/tailscale,
  `--network host`, `--cap-add NET_ADMIN`, `/dev/net/tun`, state volume
  `tailscale-state`, `--entrypoint tailscaled` — NOT the stock entrypoint,
  whose boot script kills `tailscale up` at 60s and crash-loops the
  nodekey). Node `dev-vm` = `<tailnet-host>`; advertises subnet route
  `<lan-ip>/24` (approved in the admin console) so the relay's LAN URL
  (`http://<lan-host>:3300`) works both direct on the home LAN and
  remotely through the tailnet. Phone: Tailscale app with split tunneling
  (include mode) for Outpost-Pi; WireGuard must be fully off (single
  Android VPN slot). **After every app uninstall/reinstall (incl.
  sideloads), re-toggle Outpost-Pi in Tailscale's split-tunnel list** —
  Android binds entries by app UID, reinstalls mint a new UID, and the
  stale checkmark looks applied but the app's traffic never enters the
  tunnel (works on WiFi, permanent relay-offline on cellular). Full setup + incident notes:
  `.work/session-notes/2026-07-26-tailscale-deploy-and-phone-routing-incident.md`.

### Paired wire changes (deploy together)

The 0.1.0 Outpost-Pi rebrand release introduced wire-stable identifier
renames that are **version-paired** — mixed versions break:
- **Auth domain-separation** (`app-0.1.0` ↔ `relay-0.1.0`): app signs
  `outpost-pi-relay-auth-v1\n` ++ nonce; relay verifies the same. Hard
  cutover — old `remote-pi-relay-auth-v1` signatures are rejected. Old app
  + new relay (or vice versa) fails the WS handshake.
- **`to_room` required** (`relay-0.1.0` ↔ `extension-0.1.0` sender): the
  relay rejects `pi_envelope` frames with empty/missing `to_room` as
  `bad_envelope`. Sender-side room-targeting has since shipped
  (`story-to-room-sender-side-room-targeting`): the extension threads the
  destination sibling's actual room through every `sendEnvelopeToPi` call
  site (`broker_remote.ts`). This only affects **cross-PC agent mesh**
  (Pi↔Pi `agent_send`); the app↔pi path is unaffected.
- **Cockpit control-RPC discriminator** (`extension-0.1.0` ↔ `cockpit-0.1.0`):
  the NUL-prefixed control string is now `\x00outpost-pi-ctrl:` and the
  structured type is `outpost_pi_control`. Hard cutover — old cockpit + new
  extension (or vice versa) break the control channel.
- **Owner-channel E2E** (target v0.3.0; app ↔ extension): `pair_request` and
  `pair_ok` carry signed ephemeral-DH fields (`pair_request` additionally
  carries `token_id` + `pair_mac`, an HMAC proof of QR-token knowledge — the
  raw pair token never crosses the wire), and post-pairing `outer.ct`
  payloads are sealed frames rather than base64 plaintext. The extension
  rejects unauthenticated `pair_request`s (`pair_error token_unknown` /
  `bad_dh_sig`); it also rejects plaintext post-key frames and AEAD/replay
  failures, detaching the channel subscription after five consecutive
  failures — the NEXT frame from the keyed owner simply reattaches with the
  same persisted channel keys (AEAD remains the security boundary; forged
  frames never dispatch). Re-pairing is the recovery path for key loss or a
  half-established pairing, not for transient frame failures. Existing
  pairings have no channel key, so their frames are dropped and operators
  must re-pair once at cutover. The relay remains untouched because `ct`
  stays opaque base64; no relay version pairing is required. Safe deploy
  order: rebuild the extension `dist/`, then fully restart Pi (not
  `/reload`), then sideload the app.
- **Storage/keyring/launchd identifiers** (hard cutover, destructive): Hive
  box names (`dev.outpostpi.*`), keyring service (`dev.outpostpi.pi`), owner
  identity (`dev.outpostpi.owner.identity`), launchd label
  (`dev.outpostpi.supervisord`), QR URI scheme (`outpostpi://`), and env
  vars (`OUTPOST_PI_*`/`OUTPOSTPI_*`) all renamed. The phone loses persisted
  pairing data and re-pairs; the old launchd daemon is orphaned under the
  old label and must be manually cleaned (`launchctl bootout
  gui/$(id -u)/dev.remotepi.supervisord`).

Safe deploy order: **relay first**, then **full Pi process restart**
(not `/reload` — see below), then sideload the app, then upgrade Cockpit.
Cockpit 0.1.0 is part of the paired deployment because its control channel
(`\x00outpost-pi-ctrl:` / `outpost_pi_control` / `outpost-pi:*` events) is
also hard-cutover — old Cockpit + new extension break the control channel.

### Reload vs restart (pi-extension)

`/reload` in the pi TUI does **not** re-import `dist/index.js` for a
`type: module` (ESM) extension. A source edit is only picked up by a **full
pi process restart** (quit + relaunch), not `/reload`.

**Root cause (verified 2026-07-31 against jiti 2.7.0):** `/reload` does call
`clearExtensionCache()` (clears pi's factory Map) and then `jiti.import()`,
so pi's own cache IS cleared. But jiti's async import path for a
`type: module` `.js` file takes the `nativeImport` branch:
`nativeImport = (id) => import(id)` — Node's native dynamic `import()`, whose
ESM module cache is **immutable at runtime** (no API to invalidate it).
`moduleCache: false` (which pi sets) only clears the CJS `require.cache`,
not the ESM cache. So the stale module from the first load is returned on
every subsequent `/reload`. The earlier 2026-07-07 empirical note
(hypothesizing a retained factory or incomplete `/reload` path) was
mistaken about the *mechanism* but correct about the *result*.

### Hot-reloading dist/ via process restart (interactive session)

Since `/reload` cannot load new ESM `dist/` code, the extension ships a
**turn_end sentinel + process restart** mechanism that makes a full restart
cheap enough to use as a hot-reload from within a turn (e.g. while working
via mobile):

1. Rebuild `dist/` (`./node_modules/.bin/tsc` or `corepack pnpm build`).
2. Enable the toggle (one-time, persists): `./scripts/hot-reload.sh on`
3. Arm the restart: `./scripts/hot-reload.sh arm` (touches
   `~/.pi/remote/.restart-pending`). Or combine: `./scripts/hot-reload.sh on+arm`.
4. On the next `turn_end` (after the response fully streams), the extension
   checks: toggle enabled + sentinel present → consumes the sentinel and
   schedules `SIGTERM` after a 500ms flush delay.
5. pi's `SIGTERM` handler fires `session_shutdown` (publishes `working=false`,
   closes the relay cleanly) then `process.exit(0)`.
6. `scripts/pi-restart-loop.sh` (run under tmux with `RESTART_ON_EXIT_ZERO=1`)
   sees the exit and relaunches `pi --continue` with a fresh ESM cache.
   The relay reconnects in ~2s; the app converges to idle.

The agent's response fully streams before the restart — no cut-short turn.

```bash
# Start pi under the restart loop (run once):
tmux new -d -s outpost 'cd /home/agent/projects/outpost_pi && RESTART_ON_EXIT_ZERO=1 ./scripts/pi-restart-loop.sh'
tmux attach -t outpost

# Manage the hot-reload toggle:
./scripts/hot-reload.sh on       # enable (persistent)
./scripts/hot-reload.sh off      # disable (sentinels ignored)
./scripts/hot-reload.sh arm      # request restart at next turn_end
./scripts/hot-reload.sh on+arm   # enable + arm in one step
./scripts/hot-reload.sh status   # show state
```

A plain `kill -TERM $(pgrep -x pi)` also triggers the same graceful shutdown +
relaunch when running under the loop, but skips the turn_end flush (the
current turn's response may be cut short). Prefer the sentinel for
in-turn reloads.

### Relay container commands

```bash
# build from current fork source
docker build -t outpost-pi-relay:0.1.0 relay/
# run (reproduces the live container's config: port 3300→3000, named volume,
# retroactive file log + cross-side debug correlation)
docker run -d --name outpost-pi-relay -p 3300:3000 \
  -v outpost-pi-data:/data \
  -e OUTPOSTPI_RELAY_PORT=3000 \
  -e OUTPOSTPI_MESH_DB_PATH=/data/mesh.db \
  -e OUTPOSTPI_RELAY_LOG_DIR=/data/logs \
  -e RUST_LOG="info,relay=debug" \
  --restart unless-stopped outpost-pi-relay:0.1.0
# rebuild from updated source + swap in
docker stop outpost-pi-relay && docker rm outpost-pi-relay  # then build + run
# read the persistent relay log (survives scroll/restart; daily-rotated)
docker exec outpost-pi-relay tail -f /data/logs/relay.log.$(date -u +%F)
```

**First 0.1.0 relay cutover:** on a host still running the pre-rebrand
container `remote-pi-relay` on port 3300, `docker run -p 3300:3000` fails
(port occupied). Stop and remove the old container first:
```bash
docker stop remote-pi-relay && docker rm remote-pi-relay
# then build + run outpost-pi-relay:0.1.0 as above
```

Without `OUTPOSTPI_RELAY_LOG_DIR`, logging is stdout-only (lost on
scroll/restart — the pre-0.1.0 gap). `RUST_LOG` defaults to `info`; the
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

Toolchain: Flutter at `~/projects/outpost_pi/.tools/flutter`, JDK 21
(`JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`), Android SDK API 36 at
`/opt/android-sdk`. Full build-path notes in `.agents/skills/flutter-mobile/SKILL.md`.

### Sideload to phone

The phone is attached to a workstation, not the VM. After building on the VM,
copy the APK to the workstation and install with `adb` (USB debugging on):
```bash
scp app/build/app/outputs/flutter-apk/app-release.apk <workstation>:~/app.apk
# on the workstation:
# First 0.1.0 sideload: the applicationId changed (work.jacobmoura.remotepi →
# dev.kevoun.outpostpi), so `adb install -r` installs ALONGSIDE the old app
# (no INSTALL_FAILED_UPDATE_INCOMPATIBLE). Uninstall the old package first:
adb uninstall work.jacobmoura.remotepi
adb install ~/app.apk
# Subsequent 0.1.x updates: `adb install -r ~/app.apk` (-r keeps data)
```
The app's `pubspec.yaml` version is NOT bumped by `release-deploy`; bump it
manually before building when shipping a new version.
