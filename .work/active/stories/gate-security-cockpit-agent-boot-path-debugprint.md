---
id: gate-security-cockpit-agent-boot-path-debugprint
kind: story
stage: review
tags: [security, cockpit]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-27
updated: 2026-07-28
---

# Agent boot debugPrints the absolute workspace path

Severity: Low (parked per gate_finding_routing).
`cockpit/lib/app/cockpit/ui/session/agent_session.dart:263` unconditionally
`debugPrint`s the absolute `workingDirectory` on every agent boot, exposing
workspace paths to console/collected diagnostics despite the release's
path-redaction hardening. Fix: content-free boot diagnostic (or remove it) +
a debug-output canary with a path-bearing workspace.

## Implementation notes

- Changed `cockpit/lib/app/cockpit/ui/session/agent_session.dart` to emit only the session ID in the boot diagnostic.
- Added a canary in `cockpit/test/ui/agent_session_turn_projection_test.dart` using a path-bearing workspace and capturing `debugPrint` output.
- Verification: `flutter analyze` and `flutter test` pass after all three stories are implemented.
- Parked issue: none.
