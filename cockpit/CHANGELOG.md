# Changelog — Outpost-Pi Cockpit

Format based on [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versions follow `version:` in `pubspec.yaml` (SSOT). The `cockpit-v*` GitHub
Release workflow derives its release notes from the first version section in
this file.

## [Unreleased]

### Changed — Outpost-Pi rebrand
- Product identity migration: macOS app ID `work.jacobmoura.cockpit` →
  `dev.kevoun.outpostpi.cockpit`, Windows display name **Remote Pi Cockpit** →
  **Outpost-Pi Cockpit**, and onboarding installs the `outpost-pi` extension
  (was `remote-pi`). The control-RPC discriminator moves to
  `\x00outpost-pi-ctrl:` / `outpost_pi_control` (hard cutover — old Cockpit +
  new extension break the control channel; see repo-root `AGENTS.md` paired
  wire changes). The pre-rebrand `cockpit-v1.x` series is superseded; this is
  the first Outpost-Pi Cockpit release family.

### Added
- **Self-update (plan 47):** Cockpit now updates itself on **macOS**
  through Sparkle (`auto_updater` package): checks and downloads in the
  background, shows "restart to install" in the rail card, and swaps the binary
  on restart. **Linux** retains the warning + manual download (`latest.json`).
  CI publishes `appcast-macos.xml` (EdDSA-signed) alongside `latest.json`.
  **Windows** auto-update is **not yet active**: the locked `auto_updater_windows`
  plugin does not expose the WinSparkle build-version API needed for a proven
  version contract, so the Windows appcast is intentionally not published.
  Windows users update by manual reinstall until the plugin is upgraded.

> Release note: Sparkle compares the **build number** (`CFBundleVersion`, the
> `+n`) — increment `+n` in `pubspec.yaml` on every release or macOS will not
> detect the new version.

## [1.1.0] — 2026-06-12

### Changed
- Interface fully translated to **English** (all on-screen text, tooltips,
  dialogs, notifications and error messages). The machine name in the rail now
  shows the real hostname.

## [1.0.0] — 2026-06-12

First distributable Cockpit release (Remote Pi desktop client).

### Added
- Release identity: app ID `work.jacobmoura.cockpit`, display name
  **Remote Pi Cockpit** on all three platforms.
- macOS: Hardened Runtime in Release; build signed with Developer ID +
  notarization + staple (universal x86_64+arm64 DMG).
- Linux: desktop integration (`.desktop`, hicolor icons, AppStream
  `metainfo.xml`) and window controls in the custom title bar.
- Windows: executable metadata (CompanyName/ProductName) and window controls
  in the custom title bar.
- Packaging through Fastforge: `distribute_options.yaml` + `make_config.yaml`
  for dmg/exe/deb/rpm.

### App functionality (MVP)
- Workspace pane multiplexer: agents (`pi --mode rpc`) and terminals
  side by side, with splits and tabs.
- File tree with context menu (create an agent/terminal in a directory).
- Worktrees per workspace (clones the pane structure for the fork).
- Onboarding that checks/installs `pi`, the `remote-pi` extension, and supervisor.
- Daemon scheduling and connectivity (pairing through relay).
