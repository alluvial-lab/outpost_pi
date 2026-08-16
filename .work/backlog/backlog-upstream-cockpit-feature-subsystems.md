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

1. **Terminal state persistence + profiles** (`a94b304e` scrollback/cwd
   restore via OSC 7; `bfc60257`/`8de67f27` profile discovery + default
   selector) — direct daily value for long agent sessions; M.
2. **Task runner** (`3792ba6d` et al., tasks.json JSONC + PTY + watch) —
   build/dev executor with live output tabs; self-contained, M-L.
3. **Git/source-control layer** (`1263f2a8` sync/pull/push/merge-to-parent
   + diff viewer; worktrees `03ed6965`; realms `6e4f5b82`; multi-root
   `6ea98bcf`) — large; we currently have little of it; L, staged.
4. **Editor depth** (`bfa2f23e` LSP semantic highlight + goto-def;
   `843b51f4` SCM gutter; `02ff99f8` Cmd+F in-viewer) — M each, on our
   editor surfaces.
5. **Self-update infrastructure** (Sparkle/WinSparkle + frequency settings
   `4218eaf1`; bootstrapper `191f80dd`) — matters for public artifact
   distribution; we already have macOS self-update (see
   `cockpit-macos-self-update-changelog-consistency`); evaluate Windows
   updater only; M.

Explicitly not adopted (do not re-evaluate without new cause): i18n/slang,
multi-theme system, navigator webview, DB panels, Copilot, sounds, commit-
message harness integration.

Upstream reference: `upstream/main` @ 8fa8df8b (2026-08-15 sweep; full
dispositions in `feature-upstream-remote-pi-harvest`).
