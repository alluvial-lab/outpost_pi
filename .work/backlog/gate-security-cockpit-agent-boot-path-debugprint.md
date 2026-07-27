---
id: gate-security-cockpit-agent-boot-path-debugprint
created: 2026-07-27
updated: 2026-07-27
tags: [security]
gate_origin: security
---

# Agent boot debugPrints the absolute workspace path

Severity: Low (parked per gate_finding_routing).
`cockpit/lib/app/cockpit/ui/session/agent_session.dart:263` unconditionally
`debugPrint`s the absolute `workingDirectory` on every agent boot, exposing
workspace paths to console/collected diagnostics despite the release's
path-redaction hardening. Fix: content-free boot diagnostic (or remove it) +
a debug-output canary with a path-bearing workspace.
