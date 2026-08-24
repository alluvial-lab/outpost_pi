# Cockpit

Outpost-Pi's Flutter desktop cockpit — the workstation control surface for a
paired Pi agent session. Connects to a locally-running Pi process (driven by
the `outpost-pi` extension) and renders the agent transcript, terminal, file
browser, and remote-session controls.

## What it is

Cockpit is the desktop half of the Outpost-Pi remote-coding surface: the phone
app pairs and drives sessions; Cockpit is the rich workstation view for the same
Pi process. It emits structured `outpost_pi_control` RPC envelopes as Pi custom events,
not over the relay. The extension retains the NUL-prefixed
`\x00outpost-pi-ctrl:` form only as a compatibility decoder; Cockpit does not
emit that legacy form.

## Key surfaces

- **Workspace / transcript** — agent session view, terminal/PTY, file browser.
- **Settings** — relay endpoint, daemon/auto-start config.
- **Remote-session control** — the control-RPC channel to the Pi extension.

## Setup / build / run

Flutter is **not** on `PATH` on the dev VM, and Cockpit needs `pub get --offline`
(three deps are git-overridden). The full, current build workflow — toolchain
paths, `PUB_CACHE`, and the exact commands — lives in
`.agents/skills/flutter-desktop-cockpit/SKILL.md`; read it before building or
testing. In short:

```bash
export PUB_CACHE=~/projects/outpost_pi/.pub-cache
~/projects/outpost_pi/.tools/flutter/bin/flutter pub get --offline
~/projects/outpost_pi/.tools/flutter/bin/flutter analyze
~/projects/outpost_pi/.tools/flutter/bin/flutter test
```

## Canonical references

- `AGENTS.md` (repo root) — build/test commands, deployment, paired-wire cutover.
- `cockpit/CLAUDE.md` — cockpit-specific workflow and module layout.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — Flutter desktop lifecycle,
  shadcn/modular/Hive patterns, terminal/PTY, plugin surfaces, and the full
  dev-VM build/test command set.

This README is operator orientation. For agent routing, workflow, and
implementation rules, see `CLAUDE.md` and the skill reference above.
