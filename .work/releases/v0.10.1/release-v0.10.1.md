---
id: release-v0.10.1
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.10.1
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Release v0.10.1 (patch lane)

Single-fix patch: connect-attempt deadline (story-connect-attempt-deadline,
capture-diagnosed hung-connect wedge). 15s deadline → existing failure path;
resume reconciliation for doze-aged connecting states. Suites 989/989,
break-it-proven.

- Date shipped: 2026-08-27 · Mapping: tag-based · published via fresh
  `gh release create --latest` (draft→API-publish marker bug avoided)
- Verification: unit+full suites green; field UAT = operator soak (the
  wedge class recurs on flaky WiFi; the fix makes the ladder re-engage)
- Items: 1 (fix lane — no gate cycle per patch-lane policy; the change is
  bounded to the connect path with its own regression)
