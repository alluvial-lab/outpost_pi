---
id: backlog-pattern-anchor-refresh-v0110
created: 2026-10-05
updated: 2026-10-05
tags: [docs, workflow]
---

# Refresh SDK projection pattern references after compatibility cleanup

The SDK 0.84 compatibility cleanup removed private hydration code and shifted implementation paths; pattern-skill anchors for session identity and stale-capability references need one refresh pass over the same module/event, keeping each item's distinct invariants. Folded from two gate-docs pattern findings.

Consolidated 2026-10-05 by operator-confirmed groom merge from: gate-docs-pattern-session-identity-anchors, gate-docs-pattern-stale-capability-anchors-v0110.
Scope-promote via /agile-workflow:scope when wanted.
