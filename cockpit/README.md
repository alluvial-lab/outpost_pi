# Cockpit

Outpost-Pi's Flutter desktop cockpit — the workstation control surface for a
paired Pi agent session. Connects to a locally-running Pi process (driven by
the `outpost-pi` extension) and renders the agent transcript, terminal, file
browser, and remote-session controls.

## What it is

Cockpit is the desktop half of the Outpost-Pi remote-coding surface: the phone
app pairs and drives sessions; Cockpit is the rich workstation view for the same
Pi process. It talks to the extension over the Pi control RPC channel
(`\x00outpost-pi-ctrl:` control frames + the generated `outpost_pi_control`
schema), not over the relay.

## Setup / build / run

Requires Flutter and a JDK; see the project root `AGENTS.md` for the toolchain
versions used on the dev VM.

```bash
# from cockpit/
flutter pub get
flutter analyze
flutter test
flutter build macos     # or windows / linux
```

## Key surfaces

- **Workspace / transcript** — agent session view, terminal/PTY, file browser.
- **Settings** — relay endpoint, owner identity, daemon/auto-start config.
- **Remote-session control** — the control-RPC channel to the Pi extension.

## Canonical references

- `AGENTS.md` (repo root) — build/test commands, deployment, paired-wire cutover.
- `cockpit/CLAUDE.md` — cockpit-specific workflow and module layout.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — Flutter desktop lifecycle,
  shadcn/modular/Hive patterns, terminal/PTY, and plugin surfaces.

This README is operator orientation. For agent routing, workflow, and
implementation rules, see `CLAUDE.md` and the skill reference above.
