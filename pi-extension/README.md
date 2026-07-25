<p align="center">
  <img src="https://raw.githubusercontent.com/KevounC/outpost_pi/main/branding/logo-full.svg" width="160" alt="Outpost-Pi logo" />
</p>

<h1 align="center">Outpost-Pi</h1>

> Extend the [Pi coding agent](https://github.com/earendil-works/pi) with two
> superpowers: agents that talk to each other on the same machine, and a mobile
> app that drives Pi from your phone.

**Homepage:** <https://outpost-pi.kevoun.com>

`/outpost-pi` is a single slash command that wires both at once. Run it; the
first time it asks a couple of questions and you are done. You will also need
to point it at a relay with `/outpost-pi set-relay <url>` (there is no default
relay) before the relay can connect.

## Protocol & Security

For wire format, identity model, ACK protocol, cross-PC routing, mesh
membership, and the trust model (what the relay sees and doesn't see),
read [`PROTOCOL.md`](../PROTOCOL.md) at the repo root. It is the canonical
document — this README only covers user-facing setup.

---

## Quick start

Install the extension (one-time):

```bash
pi install npm:outpost-pi
```

Then in any Pi terminal:

```text
/outpost-pi
```

The first run shows a short interactive wizard (agent name, whether to
auto-start the relay). The wizard sets your preferences but does not configure
a relay URL — run `/outpost-pi set-relay <url>` once first (there is no
default relay). On every following run, `/outpost-pi` joins the local agent
session and starts the relay automatically — no extra typing.

### Try the agent network in 30 seconds

Open **two** Pi terminals in the same directory and run `/outpost-pi` in each.
Both join the same session. Now just talk to the LLM — it has the tools.

In terminal A (say it ended up named `agent-A`):

```text
Who else is connected in our agent session? List them.
```

The LLM calls `agent_send` to `broker` with `{ type: "list_peers" }` and
replies with the names it sees.

Then, still in terminal A:

```text
Send a ping to agent-B and wait for a reply.
```

Pi calls `agent_request({ to: "agent-B", body: { type: "ping" } })`. The
message arrives in terminal B as a user-facing turn — terminal B's LLM
answers, and the reply lands back in terminal A. Two agents, one prompt
each, full round trip.

(Replace `agent-B` with whatever name terminal B reports for itself — the
wizard's default is the directory name plus a `#N` suffix on collision.)

---

## What it does

Outpost-Pi adds two independent layers on top of Pi. You can use either, or
both:

### 1) Agent network (local, same machine)

Several Pi instances running side-by-side in different terminals can discover
each other and exchange messages. Each instance is a peer in a named
*session* and gets two tools the LLM can call directly:

- `agent_send` — fire-and-forget message to another agent
- `agent_request` — send and await a reply (correlated by message id)

This is purely local: the agents talk over a Unix domain socket at
`~/.pi/remote/sessions/<session-name>/broker.sock`. No network involved.
Useful for splitting work across roles (`backend`, `frontend`, `tests`,
`orchestrator`, …) and letting them coordinate.

The first agent to enter a session becomes the *leader* (hosts the broker);
the rest are *followers*. If the leader exits, a follower automatically takes
over — the failover is invisible to the LLMs.

### 2) Mobile app (over the relay)

The companion mobile app lets you send prompts to Pi and read its responses
from your phone. The phone and the Pi process find each other through a
**relay**: a small WebSocket server that ferries messages between them.
Pairing is one-time and per device, via QR code.

Communication: WebSocket over TLS to the relay. After pairing, app↔Pi
owner-channel payloads are sealed and authenticated end to end (including
inline images), so the relay forwards them as opaque ciphertext. The relay
still sees routing metadata, and cross-PC Pi↔Pi envelopes remain relay-readable
plaintext — see [`PROTOCOL.md`](../PROTOCOL.md) for the trust model.

**Get the app** — current direct downloads and store availability while
operator-owned public releases roll out:

<https://outpost-pi.kevoun.com/#get-the-app>

---

## Mobile app actions

Beyond the chat, the app surfaces a small set of typed actions you can run
on the paired Pi session. Tap the ⚙ button next to the message input (visible
when the input is empty) to open the Quick Actions sheet:

| Action | What it does |
|---|---|
| **Compact context** | Runs `ctx.compact()` — same as `/compact` in the TUI. |
| **New session** | Runs `ctx.newSession()` — equivalent to `/new`, asks for confirmation first. |
| **Model** | Opens a model picker fed by your authenticated providers (same source the TUI uses) and switches via `pi.setModel(model)`. |
| **Thinking** | Segmented control with the 6 SDK levels (`off` · `minimal` · `low` · `medium` · `high` · `xhigh`). Changes via `pi.setThinkingLevel(level)`. |

Each action gets a structured `action_ok` / `action_error` reply so the app
can show a SnackBar on failure. Visible side-effects (chat output, model
change broadcasts, compaction notice) still flow through the normal chat
channels. The wire schema is documented in [`PROTOCOL.md`](../PROTOCOL.md)
under "App actions".

It is **not** a generic slash-command picker. The Pi SDK does not expose
programmatic invocation for most builtins (those live in the TUI's
interactive loop), so the app exposes only the actions that have a clean
SDK call. The [`pi-telegram`](https://github.com/llblab/pi-telegram) adapter
follows the same pattern.

### Images

The app can attach **one image** (camera or gallery) to a message. It's
compressed on the device and rides **inline** in the `user_message` — the
optional `images` field carries `{ data: <base64>, mime }`. The pi-extension
turns it into the SDK's multimodal content (an `ImageContent` followed by the
caption `TextContent`) and calls `sendUserMessage(content)`, so the model sees
the picture plus your text.

Whether a model accepts images is surfaced as a `vision` flag on each
`WireModel` (derived from the SDK's `Model.input` including `"image"`); the app
greys out the attach button when the active model is text-only.

The **relay is unchanged** — the image travels inline in the same owner-channel
JSON payload as the rest of the message, so there's no binary channel (large
files are a future track). The owner-channel seal protects the image along with
the text; text-only messages use the same protection.

---

## Install

Requirements: Node 20+, Pi (the host coding agent).

```bash
pi install npm:outpost-pi
```

The extension self-registers the `/outpost-pi` slash command and deploys an
agent skill that teaches the LLM how to use `agent_send` / `agent_request`.

To verify:

```text
/outpost-pi status
```

It prints a two-line snapshot: the local mesh state and the relay state
(`unconfigured` / `off` / `on`), including the effective relay URL. When the
relay is unconfigured, the status line directs you to
`/outpost-pi set-relay <url>` to persist a relay URL to user config.

---

## Using `/outpost-pi`

The bare command is the everyday entry point:

```text
/outpost-pi
```

Behavior depends on whether there's a local config for this directory:

| State | What happens |
|---|---|
| First run (no `.pi/outpost-pi/config.json`) | Interactive wizard → saves config → joins agent session → starts relay (if you opted in) |
| Returning user, auto-start enabled | Joins agent session + starts relay automatically, then prints status |
| Returning user, auto-start disabled | Prints status only; join/relay must be run manually |

The wizard asks three questions:

1. **Agent name** — how other agents will address you in `agent_send` /
   `agent_request`. Defaults to the directory name.
2. **Default session** — the name of the agent-network room for this
   directory. Multiple terminals in the same directory join the same session.
3. **Auto-start relay (for mobile app access)?** — `Yes` if you want
   `/outpost-pi` to also connect to the relay so the mobile app can reach this
   Pi. `No` for local-only use (agent network without mobile access).

Re-run the wizard later with `/outpost-pi setup`.

---

## Pairing a mobile device

Once the relay is up (`/outpost-pi relay status` shows `started` or `paired`):

```text
/outpost-pi pair
```

`/outpost-pi pair` shows the QR code and pairing URI in an interactive TUI dialog. Scan the QR code with the Outpost-Pi mobile app. Non-TUI invocation warns and does not display a QR; the `OUTPOST_PI_PAIR_CODE_FILE` file seam is reserved for E2E harness use.
Pairing is **per machine** — once a device is paired, every Pi process on
this machine accepts it (it lives in `~/.pi/remote/peers.json`).

To list paired devices:

```text
/outpost-pi devices
```

To remove one:

```text
/outpost-pi revoke <shortid>
```

The shortid is the first 8 chars shown by `devices`.

---

## The relay

The relay is the only network-touching piece of Outpost-Pi. After pairing,
app↔Pi owner-channel payloads are sealed and authenticated end to end, so the
relay forwards their `ct` as opaque ciphertext. It still sees connection and
routing metadata — which keypair is online, room/cwd identifiers, message
timing, and sizes — and cross-PC Pi↔Pi envelopes remain relay-readable
plaintext.

You must self-host a relay. TLS + Ed25519 pairing/relay authentication and the
owner-channel E2E seal are built in; there is no IP allow-listing or VPN gating.
Use a VPN for additional network access control.

### Self-host a relay

Run the relay yourself in Docker and put it behind a VPN like
[Tailscale](https://tailscale.com), [WireGuard](https://www.wireguard.com),
or your own VPC. Because the relay's network-level protection is just TLS +
keypair authentication, layering a VPN on top means **only your devices** can
even reach the WebSocket port — defense in depth.

Quick Docker outline (see the
[relay README](https://github.com/KevounC/outpost_pi/blob/main/relay/README.md#self-hosted-relay-recommended-for-privacy)
for the full setup, environment variables, and reverse-proxy guidance):

```bash
docker build -t outpost-pi-relay relay/
docker run -d \
  --name outpost-pi-relay \
  -p 3000:3000 \
  --restart unless-stopped \
  outpost-pi-relay
```

Bind the container to your VPN interface, terminate TLS in a reverse proxy,
and point both your Pi and your phone at the resulting `https://…` URL.

### Pointing Pi at your own relay

Once your relay is reachable, tell the extension:

```text
/outpost-pi set-relay https://relay.yourdomain.tld
```

The URL **must** be `http://` or `https://` — `ws://` / `wss://` are
rejected at validation. The extension converts to WebSocket internally when
it opens the connection. Same canonical form for the mobile app and any
self-hosting docs: paste the URL your reverse proxy exposes.

This writes `~/.pi/remote/config.json` with `{ "relay": "..." }`. Resolution
order (highest precedence first):

1. `OUTPOST_PI_RELAY` environment variable (CI / one-off overrides)
2. `~/.pi/remote/config.json`

Without either source, relay-dependent commands stay unconfigured and direct
users to `/outpost-pi set-relay <url>`.

Verify the relay state with:

```text
/outpost-pi status
```

If you change the URL while connected, run `/outpost-pi stop`, then
`/outpost-pi` to start it again.

The mobile app has its own relay-URL setting in its preferences pane — keep
both pointing at the same relay.

---

## Agent network: deeper look

Each session is one Unix-domain-socket broker plus N peers. The broker
multiplexes messages by `to` name and broadcasts system events
(`peer_joined`, `peer_left`).

Inside the LLM, the agent skill registers two tools:

```jsonc
// Fire-and-forget
agent_send({
  to: "backend",      // peer name (or array for multicast)
  body: { task: "add /healthz endpoint" },
  re: "<id>"          // optional — set when replying to a previous request
})

// Send + await reply (default 30s timeout)
agent_request({
  to: "backend",
  body: { question: "is the migration applied?" }
})
```

The wire format is a 5-field envelope `{ from, to, id, re, body }` serialized
as one JSON line per message. The leader's broker writes an `audit.jsonl`
log at `~/.pi/remote/sessions/<name>/audit.jsonl` for postmortem inspection.

Useful commands:

| Command | What it does |
|---|---|
| `/outpost-pi join [name]` | Join (or create) a session — only needed manually if `auto_start_relay=false` |
| `/outpost-pi leave` | Leave the current session |
| `/outpost-pi sessions` | List local sessions and which are live |
| `/outpost-pi rename <new>` | Rename this agent in the current session |

Name collisions inside a session get a numeric suffix automatically
(`backend`, `backend#2`, `backend#3`). The broker assigns it and returns the
real name to the peer.

---

## Command reference

### Local session (one Pi, one terminal)

| Command | Description |
|---|---|
| `/outpost-pi` | Connect (join local mesh + start relay), or run setup on first use |
| `/outpost-pi setup` | Run the setup wizard and update local config |
| `/outpost-pi status` | Show local mesh + relay status |
| `/outpost-pi stop` | Stop everything for **this** terminal (mesh + relay) |
| `/outpost-pi pair` | Show QR code + copy-paste pairing URI for a new mobile device |
| `/outpost-pi devices` | List paired mobile devices (online/offline per device) |
| `/outpost-pi revoke <shortid>` | Revoke a paired device by its shortid |
| `/outpost-pi set-relay <url>` | Persist a new relay URL (http:// or https://) |

### Daemon fleet (one supervisor, N background Pis — see [Daemon mode](#daemon-mode))

| Command | Description |
|---|---|
| `/outpost-pi create <cwd> [--name X]` | Register a folder as a daemon |
| `/outpost-pi remove <id>` | Unregister a daemon (local config preserved) |
| `/outpost-pi daemons` | List registered daemons + state |
| `/outpost-pi daemon start` | Start every registered daemon |
| `/outpost-pi daemon stop` | Stop every running daemon (`/outpost-pi stop` stops only the local terminal) |
| `/outpost-pi daemon restart` | Stop + start all daemons |
| `/outpost-pi daemon status` | Detailed runtime status (pid, uptime, restart count) |
| `/outpost-pi daemon send <id> "<text>"` | Send a prompt to a specific daemon |
| `/outpost-pi cron add <id> "<expr>" "<prompt>"` | Schedule a recurring prompt (`--tz`, `--wake`, `--no-skip-busy`, `--catchup`) |
| `/outpost-pi cron list` | List scheduled jobs (schedule, enabled, next run, last status) |
| `/outpost-pi cron run <jobId>` | Fire a job now (ignores its schedule) |
| `/outpost-pi cron enable\|disable <jobId>` | Toggle a job on/off |
| `/outpost-pi cron remove <jobId>` | Delete a job |
| `/outpost-pi cron log [<jobId>] [--tail N]` | Read the fire/skip audit log |
| `/outpost-pi install` | Install `pi-supervisord` as a system service |
| `/outpost-pi uninstall` | Remove the system service (registry preserved) |

All commands above work both as Pi slash commands (interactive) and as
shell-level `outpost-pi <subcommand>` when the package is installed
globally (`npm install -g outpost-pi`).

### Scheduled prompts (`cron`)

`outpost-pi cron` schedules **recurring prompts** to daemons through the
supervisor — e.g. a daily "summarise new PRs". Output flows fire-and-forget to
the mesh/app like any prompt; the cron layer only audits the dispatch.

- **Schedule** is a cron expression (croner syntax; an optional 6th *seconds*
  field is supported), with an optional IANA timezone via `--tz`:

  ```sh
  outpost-pi cron add a1b2c3d4 "0 9 * * *" "Summarise new PRs" --tz America/Sao_Paulo
  ```

- **Minimum interval is 60s** — more frequent schedules are rejected (guards
  token cost + pileup). A fire is **skipped when the daemon is mid-turn**
  (`--no-skip-busy` to override); `--wake` starts a stopped daemon first;
  `--catchup` runs once on supervisor start if the previous run was missed.
- **Prerequisite**: the supervisor must run as a service (`outpost-pi install`).
  Without it there is no scheduler, and `cron` commands say so instead of
  silently pretending to schedule.
- **Audit**: every fire **and** every skip appends one line to
  `~/.pi/remote/cron.jsonl` with a `result` of `delivered`,
  `woke_and_delivered`, `deliver_failed`, `skipped_busy`, `skipped_down`, or
  `skipped_disabled` — read it with `outpost-pi cron log`.

Step-by-step walkthrough: the [daemon tutorial](https://outpost-pi.kevoun.com/tutorials/daemon).

### Footer + title

- `📡 local (N)` — current agent session and peer count (local mesh)
- `🟢 relay` — relay connected, at least one device paired (globally)
- `🟡 relay waiting for pairing` — relay connected, no device paired yet
- `📱 <shortid>` — a mobile device is actively connected right now

Window title: `<agent-name> · On` when relay is up, `<agent-name> · Off`
otherwise. Tells your terminals apart at a glance in `cmux`/`tmux`/iTerm
tabs.

---

## Daemon mode

When you want a Pi to keep running in the background (responding to
mobile prompts at 3am, processing cron jobs, monitoring a folder while
you're not at the keyboard), promote it to a **daemon** managed by a
single OS-level supervisor.

See [`docs/daemon.md`](./docs/daemon.md) for troubleshooting.

### One-time setup

```bash
# Install the package globally so `outpost-pi` and `pi-supervisord`
# are on your PATH (`pi install npm:outpost-pi` alone makes the Pi
# extension available but does NOT expose the CLI binaries — see
# https://docs.npmjs.com/cli/v10/configuring-npm/package-json#bin).
npm install -g outpost-pi

# Install the supervisor as a user-level system service. Linux uses
# systemd --user; macOS uses launchd LaunchAgent. Both auto-start at
# login and survive reboots.
outpost-pi install
```

The `install` command:
- Writes `~/.config/systemd/user/outpost-pi-supervisord.service` (Linux)
  or `~/Library/LaunchAgents/dev.outpostpi.supervisord.plist` (macOS)
- Activates it via `systemctl --user enable --now` or `launchctl bootstrap`
- The supervisor starts immediately and re-starts on every login

### Per-folder workflow

For each agent you want to keep alive 24/7:

```bash
# 1. Configure the agent interactively first (one time).
cd ~/Movies
pi                                 # /outpost-pi → setup wizard, /outpost-pi pair, etc

# 2. Promote to a daemon. The id is derived from the cwd
#    (sha256(realpath)[:8]), stable across machines.
outpost-pi create ~/Movies --name "Video Editor"
# → Daemon registered: id=4e39152d name="Video Editor" cwd=/Users/x/Movies

# 3. Start it (supervisor spawns `pi --mode rpc` for this folder).
outpost-pi daemon start
```

Now you can:

```bash
outpost-pi daemons                  # list + state
outpost-pi daemon status            # uptime, pid, restart count
outpost-pi daemon send 4e39152d "Cut the first 30 seconds of latest clip"
outpost-pi daemon stop              # stop all
outpost-pi daemon restart           # restart all
```

The agent receives the prompt as if a user typed it; its response flows
back through the relay/mesh you configured during interactive setup —
mobile app sees it live, other agents on the same machine can see it
via the local UDS mesh.

### Removing or uninstalling

```bash
outpost-pi remove <id>              # unregister one daemon (config preserved)
outpost-pi uninstall                # remove the supervisor service (registry kept)
```

`uninstall` is reversible — re-running `install` later brings every
registered daemon back. To wipe the registry entirely, `rm
~/.pi/remote/daemons.json`.

### Where to find logs

| Platform | Command |
|---|---|
| Linux | `journalctl --user -u outpost-pi-supervisord -f` |
| macOS | `tail -f ~/.pi/remote/supervisord.log` |

Each spawned daemon's stderr is forwarded into the supervisor's log
with a `[<cwd>]` prefix, so a single log stream shows every agent.

### Caveats (plan/26 trade-offs)

- **Tool approval is not gated.** Daemons inherit the same Pi config
  the interactive run uses — Bash, Edit, Write etc. all execute without
  prompting. Configure Pi's tool permissions to taste before promoting
  a folder to daemon.
- **Pairing still happens interactively.** Daemons don't show a QR
  themselves; the keypair + paired devices come from the prior `pi`
  session in the same folder.
- **Single supervisor.** If `pi-supervisord` crashes all daemons go
  down with it. systemd/launchd restarts it within seconds; daemons
  come back automatically.
- **One daemon per cwd.** The `roomIdForCwd` derivation makes daemons
  by-path; two daemons in the same folder is rejected at `create` time.

---

## Configuration files

| Path | Scope | What's in it |
|---|---|---|
| `<cwd>/.pi/outpost-pi/config.json` | Per-directory | `agent_name`, `session_name`, `auto_start_relay` |
| `~/.pi/remote/config.json` | Per-user | `relay` URL |
| `~/.pi/remote/peers.json` | Per-machine | Paired mobile devices |
| `~/.pi/remote/sessions/<name>/` | Per-session | Broker socket + `audit.jsonl` |
| `~/.pi/remote/skills/agent-network/SKILL.md` | Per-user | Agent skill the LLM reads |

Override the relay for a single run without persisting:

```bash
OUTPOST_PI_RELAY=https://staging.example.tld pi
```

---

## Troubleshooting

**Footer says `🟡 relay waiting for pairing` even though I paired a device.**
The icon reflects whether *any* device has been paired on this machine, not
whether one is connected right now. If you really have a paired device in
`/outpost-pi devices`, restart Pi — the cache may be stale (fixed in current
release; report a bug if it recurs).

**Mobile app times out connecting.** Verify the same relay URL is configured
on both sides. If you self-host behind a VPN, your phone must also be on the
VPN (Tailscale on iOS/Android works fine).

**`agent_request` keeps timing out.** Default timeout is 30 s. For tasks
that legitimately take longer, the receiver should reply with `agent_send`
including `re: "<original-id>"` so the requester can correlate. The skill
explains this to the LLM automatically.

**Multiple terminals in the same directory.** Supported. They share the same
agent-network session (UDS broker) and the relay handles each Pi process
independently. If the relay refuses with `RoomAlreadyOpenError`, stop the
other terminal first.

---

## Branding

Official brand assets live in
[`/branding`](https://github.com/KevounC/outpost_pi/tree/main/branding) —
SVG sources for the logo (full, foreground, background, monochrome) plus a
banner. See the
[branding README](https://github.com/KevounC/outpost_pi/blob/main/branding/README.md)
for palette and export sizes.

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/KevounC/outpost_pi/main/branding/logo-full.svg" width="96" alt="logo-full" /><br/>
      <sub><code>logo-full</code></sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/KevounC/outpost_pi/main/branding/logo-foreground.svg" width="96" alt="logo-foreground" /><br/>
      <sub><code>logo-foreground</code></sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/KevounC/outpost_pi/main/branding/logo-monochrome.svg" width="96" alt="logo-monochrome" /><br/>
      <sub><code>logo-monochrome</code></sub>
    </td>
  </tr>
</table>

---

## Links

- Homepage: <https://outpost-pi.kevoun.com>
- Source: <https://github.com/KevounC/outpost_pi>
- Pi coding agent: <https://github.com/earendil-works/pi>
- Relay (self-hosting guide): <https://github.com/KevounC/outpost_pi/blob/main/relay/README.md>
- Issues / bugs: <https://github.com/KevounC/outpost_pi/issues>

---

## License

MIT
