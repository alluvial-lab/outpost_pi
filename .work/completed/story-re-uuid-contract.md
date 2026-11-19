---
id: story-re-uuid-contract
kind: story
completed: 2026-10-09
tags: [pi-extension, bug]
created: 2026-10-09
updated: 2026-10-09
---

# Enforce the `re` null-or-UUID contract: tool-layer fail-fast + loud broker drops

Completed (`eb60307a9`, reviewed `f12a4dc90`). Validated `re` (null or UUID) at both `agent_send` send surfaces (Pi extension tool and MCP server) reusing single-source `UUID_RE` from `session/envelope.ts`, and added loud `invalid_envelope` NACK + audit logging in the local broker so malformed envelopes fail fast instead of timing out silently. Full pre-migration story record preserved in Git history at `fa32d6abb`.
