# Changelog — Remote Pi Cockpit

Format based on [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versions follow `version:` in `pubspec.yaml` (SSOT). The `notes` field in
`latest.json` (VPS) derives from this file.

## [Unreleased]

### Added
- **Self-update (plan 47):** Cockpit now updates itself on macOS and
  Windows through Sparkle/WinSparkle (`auto_updater` package): checks and downloads in
  the background, shows "restart to install" in the rail card, and swaps the binary on
  restart. **Linux** retains the warning + manual download (`latest.json`). CI now
  publishes `appcast-macos.xml` and `appcast-windows.xml` (EdDSA-signed)
  alongside `latest.json`.

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
