---
id: idea-cockpit-dependency-independence
created: 2026-07-14
updated: 2026-07-14
tags: [cockpit, dependencies, self-ownership]
---

# Understand inherited Cockpit dependencies and chart independence

Determine what the Cockpit git dependencies hosted under Jacob Moura's GitHub account do, where Outpost-Pi uses them, and whether each remains necessary:

- `jacobaraujo7/gpt_markdown`
- `jacobaraujo7/kyroon_pty`
- `jacobaraujo7/xterm.dart`

Capture their functional role, integration surface, maintenance and licensing posture, upstream activity, available maintained alternatives, and the consequences of replacement. Chart a path toward operator-controlled dependency independence, such as adopting an appropriate upstream package, maintaining an Outpost-Pi-owned fork, vendoring a pinned implementation, or removing the dependency when its capability is no longer needed.

This is a deferred investigation, not authorization to rewrite dependency URLs blindly: the current coordinates must remain until an owned or maintained replacement exists and has a verified migration path.
