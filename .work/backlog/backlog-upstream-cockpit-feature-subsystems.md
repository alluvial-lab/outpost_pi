---
id: backlog-upstream-cockpit-feature-subsystems
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, research]
---

# Upstream cockpit feature subsystems — per-subsystem harvest evaluation

Posture change 2026-08-15: cockpit is in daily use, so upstream's IDE arc
(1.5.1 → 1.26.0) is worth evaluating per-subsystem. Constraints that bound
every evaluation:

- **Wire lock**: our cockpit speaks the paired control-RPC contract
  (`\x00outpost-pi-ctrl:`) with OUR extension; stock upstream cockpit cannot
  pair with our stack. Harvest = integration project, never adoption.
- **Brand lock**: any UI subsystem lands on Phosphor Beacon dual-mode tokens
  (upstream's 7-built-in-theme system is NOT ported; new UI ports onto OUR
  tokens).
- **Architecture**: upstream absorbed their terminal stack as internal
  modules (xterm fork → `core/terminal`, kyroon_pty → `plugins/cockpit_pty`,
  internal Rust CLI + hook); ports land against our equivalents or adapt.

Candidate subsystems, ranked by daily-use value (each needs a scoped
evaluation before any design; costs are upstream-relative):

1. **Terminal state persistence + profiles** (`545d0d20` scrollback/cwd
   restore via OSC 7; `de3b140a`/`89899af4` profile discovery + default
   selector) — direct daily value for long agent sessions; M.
2. **Task runner** (`01101eea` et al., tasks.json JSONC + PTY + watch) —
   build/dev executor with live output tabs; self-contained, M-L.
3. **Git/source-control layer** (`5da763ec` sync/pull/push/merge-to-parent
   + diff viewer; worktrees `ac6b0c94`; realms `fc51e0ef`; multi-root
   `b1c3c5fe`) — large; we currently have little of it; L, staged.
4. **Editor depth** (`3ce7322b` LSP semantic highlight + goto-def;
   `51d9a42c` SCM gutter; `91694884` Cmd+F in-viewer) — M each, on our
   editor surfaces.
5. **Self-update infrastructure** (Sparkle/WinSparkle + frequency settings
   `482239fe`; bootstrapper `fddec92c`) — matters for public artifact
   distribution; we already have macOS self-update (see
   `cockpit-macos-self-update-changelog-consistency`); evaluate Windows
   updater only; M.

Explicitly not adopted (do not re-evaluate without new cause): i18n/slang,
multi-theme system, navigator webview, DB panels, Copilot, sounds, commit-
message harness integration.

Upstream reference: `upstream/main` @ 1816bfaa (2026-08-15 sweep; full
dispositions in `feature-upstream-remote-pi-harvest`).
