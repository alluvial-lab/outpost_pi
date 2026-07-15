# Session note: cwd migration `remote_pi` → `outpost_pi`

Grounded runbook for moving the checkout directory. Verified against live
state on 2026-07-15. The operator will open a fresh pi session in
`/home/agent/projects/` (one level above the checkout) to execute this, so
the session is not sitting inside the directory it is moving.

## Why a separate session

A session running from inside `remote_pi` cannot `mv` its own cwd. A session
at `/home/agent/projects/` is one level above and can safely move the tree,
then `cd` into `outpost_pi/` for the edits, rebuilds, and relay swap.

## Ordering rules (load-bearing)

Home-directory config files that point at the checkout path must point at a
path that **exists at the moment it is read**.

- **`~/.pi/agent/trust.json`** — write BEFORE opening the new session. It is
  additive (keep the old `remote_pi` entry, add `outpost_pi`), and it is read
  at pi startup to decide whether to trust a cwd. Writing it early means the
  Phase 8 restart in `outpost_pi/` is already trusted.
- **`~/.pi/agent/settings.json`** — write AFTER the `mv`, not before. Pi reads
  it at startup to load the extension. Pointing it at `outpost_pi/pi-extension`
  before that path exists makes the session start with the extension failing to
  load — no `/outpost-pi`, no mesh tools, no relay connection. Let the
  `projects/` session start with the OLD settings (extension loads from
  `remote_pi/pi-extension`, which exists); the module stays in memory through
  the `mv` (same as the `/reload` caveat documented in AGENTS.md). Write the
  new settings after the move; it only takes effect on the next pi start.
- **`~/.bashrc`** — write AFTER the `mv`, not before. The shell sources it at
  startup; writing new paths before opening makes `PATH`/`PUB_CACHE` point at
  `outpost_pi/.tools` which does not exist yet. Write it after the move, then
  `source ~/.bashrc` (or use absolute paths) before the build-regen phase.

## Current verified state (2026-07-15)

### Outside-repo files

`~/.pi/agent/settings.json:26`:
```json
"/home/agent/projects/remote_pi/pi-extension"
```
→ becomes `/home/agent/projects/outpost_pi/pi-extension`

`~/.pi/agent/trust.json` — currently trusts `/home/agent/projects/remote_pi`.
Add `/home/agent/projects/outpost_pi` (keep the old entry).

`~/.bashrc`:
```
120:export PATH="$HOME/projects/remote_pi/.tools/flutter/bin:$PATH"
123:export PUB_CACHE="$HOME/projects/remote_pi/.pub-cache"
124:export FLUTTER_WORKSPACE="$HOME/projects/remote_pi"
126:# Remote Pi delivery debug log — must be present before the remote_pi
128:export REMOTE_PI_DEBUG_LOG=1
```
→ all `remote_pi` → `outpost_pi`; `REMOTE_PI_DEBUG_LOG` → `OUTPOST_PI_DEBUG_LOG`
(the extension code only reads the new name; the old env var is a no-op).

### Repo-local config (moves with the checkout)

`.pi/outpost-pi/config.json` and `.pi/remote-pi/config.json` both contain:
```json
{ "agent_name": "remote_pi", "auto_start_relay": true }
```
The code reads `.pi/outpost-pi/config.json`; `.pi/remote-pi/` is legacy.
Either set `agent_name` to `outpost_pi` or delete the override to let
`basename(cwd)` supply `outpost_pi` automatically.

### Relay container + volume

```
outpost-pi-relay   Up 2 days (healthy)   :3300→:3000
volume: remote-pi-data
```
Per operator decision (Q5): wipe + recreate, no state migration. Mesh
membership re-registers on next connect.

### Git remotes (do NOT change)
```
origin    git@github.com:KevounC/outpost_pi.git    (the only push target)
upstream  git@github.com:jacobaraujo7/remote_pi.git (provenance, no-push)
```

## Execution steps

### Phase 0 — Pre-checks
```bash
cd /home/agent/projects/remote_pi
git status --short --branch          # must be clean
git log --oneline origin/main..HEAD | wc -l   # note the unpushed count
```

### Phase 1 — Operator: write trust.json BEFORE opening the new session
Add `"/home/agent/projects/outpost_pi": true` to `~/.pi/agent/trust.json`
(keep the existing `remote_pi` entry).

### Phase 2 — Operator: open pi in /home/agent/projects/
The session starts with the OLD settings.json → extension loads from
`remote_pi/pi-extension` (exists) → mesh tools + relay connection alive.
The in-memory module survives the `mv`.

### Phase 3 — Move the checkout
```bash
cd /home/agent/projects
mv remote_pi outpost_pi
cd outpost_pi
```

### Phase 4 — Write home-dir config (now that the new path exists)
- `~/.pi/agent/settings.json:26` → `/home/agent/projects/outpost_pi/pi-extension`
- `~/.bashrc` lines 120, 123, 124, 128 → `outpost_pi` paths + `OUTPOST_PI_DEBUG_LOG`
- `source ~/.bashrc` (or use absolute paths to `~/projects/outpost_pi/.tools/flutter/bin/flutter`)

If the session's sandbox blocks writes to `~/` files, the operator applies
these 4 one-line edits manually.

### Phase 5 — Update repo-local durable docs (6 files, all cite the absolute path)
- `AGENTS.md:131` — extension registration path
- `AGENTS.md:250` — Flutter SDK location
- `CLAUDE.md:251` — `cd ~/Projects/remote_pi/app` (note: capital P in this one)
- `docs/agent-reference-surface.md:10` — `/home/agent/projects/remote_pi/AGENTS.md`
- `.agents/skills/flutter-mobile/SKILL.md:41` — Flutter + pub cache paths
- `.agents/skills/flutter-desktop-cockpit/SKILL.md:27-48` — Flutter + pub cache paths
- `.agents/skills/pi-extension-typescript/SKILL.md:41-45` — pnpm/npm/xdg cache paths

### Phase 6 — Update AGENTS.md relay-container commands
`AGENTS.md:209,222,225` reference the old volume/container names. Roll forward:
- `remote-pi-data` → `outpost-pi-data`
- `remote-pi-relay` → `outpost-pi-relay` (container name; the image is already `outpost-pi-relay:0.1.0`)

### Phase 7 — Fix local config
```bash
# .pi/outpost-pi/config.json — set agent_name to "outpost_pi" or remove the override
# .pi/remote-pi/config.json — legacy; can leave or delete
```

### Phase 8 — Regenerate build state (embeds the old path)
```bash
# Flutter — app + cockpit
rm -rf app/.dart_tool cockpit/.dart_tool app/build cockpit/build
cd app && export PUB_CACHE=~/projects/outpost_pi/.pub-cache && ~/projects/outpost_pi/.tools/flutter/bin/flutter pub get && cd ..
cd cockpit && ~/projects/outpost_pi/.tools/flutter/bin/flutter pub get --offline && cd ..
# pi-extension
cd pi-extension
export PNPM_HOME=~/projects/outpost_pi/.pnpm-store npm_config_cache=~/projects/outpost_pi/.npm-cache XDG_CACHE_HOME=~/projects/outpost_pi/.xdg-cache
corepack pnpm install && corepack pnpm build
cd ..
```

### Phase 9 — Relay volume swap (wipe + recreate, no migration)
```bash
docker stop outpost-pi-relay && docker rm outpost-pi-relay
docker volume rm remote-pi-data
docker volume create outpost-pi-data
docker build -t outpost-pi-relay:0.1.0 relay/
docker run -d --name outpost-pi-relay -p 3300:3000 \
  -v outpost-pi-data:/data \
  -e OUTPOSTPI_RELAY_PORT=3000 \
  -e OUTPOSTPI_MESH_DB_PATH=/data/mesh.db \
  -e OUTPOSTPI_RELAY_LOG_DIR=/data/logs \
  -e RUST_LOG="info,relay=debug" \
  --restart unless-stopped outpost-pi-relay:0.1.0
```

### Phase 10 — Commit the doc + config changes
```bash
git add AGENTS.md CLAUDE.md docs/agent-reference-surface.md \
  .agents/skills/flutter-mobile/SKILL.md \
  .agents/skills/flutter-desktop-cockpit/SKILL.md \
  .agents/skills/pi-extension-typescript/SKILL.md \
  .pi/outpost-pi/config.json
git commit -m "ops: relocate checkout remote_pi -> outpost_pi (path refs + volume)"
```

### Phase 11 — Operator: restart pi from the new path
```bash
cd /home/agent/projects/outpost_pi
pi   # full restart, NOT /reload
```

### Phase 12 — Verify
- `/outpost-pi` loads the extension from the new path
- `Mesh name: outpost_pi` (was `remote_pi` — cwd-derived default changes)
- Relay connected (`outpost-pi-relay` healthy on `:3300`)
- `which flutter` resolves under `outpost_pi/.tools/flutter`
- `git remote -v` shows `origin` → `KevounC/outpost_pi`, `upstream` → `jacobaraujo7/remote_pi`
- Re-pair the phone if needed (room IDs are cwd-derived; the mobile app's
  stored room targets the old room → appears offline until re-paired)

## What NOT to touch

- `LICENSE`, `NOTICE`, README acknowledgements — provenance, intentional
- `upstream` git remote — points to original `jacobaraujo7/remote_pi`, keep as provenance
- Historical `.work/`, release records, research attestation, CHANGELOG prose
- The `jacobaraujo7/*` Cockpit dependency URLs (tracked by parked item
  `idea-cockpit-dependency-independence`)
- Legacy wire-rejection test literals (`relay/src/auth/auth_test.rs`)

## Behavioral consequence

The default agent name and room ID both derive from `basename(cwd)`, so they
change `remote_pi` → `outpost_pi`. The phone's stored pairing targets the old
room, so it will show offline until re-paired. This is the only user-visible
impact. The relay's `mesh_versions` re-registers automatically on next connect
after the volume wipe.
