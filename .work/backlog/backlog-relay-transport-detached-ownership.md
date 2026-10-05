---
id: backlog-relay-transport-detached-ownership
created: 2026-10-05
updated: 2026-10-05
tags: [relay, workflow]
---

# Relay-transport detached-operation ownership

One transport-owned observer for detached async operations in relay client code: explicit error handling with generation checks, an owned rejection-observing dispatch helper guarding channel-generation, and transport-owned detached-operation observers on reconnect. Folded from three gate-refactor lifecycle findings about the same transport owner.

Consolidated 2026-10-05 by operator-confirmed groom merge from: gate-refactor-lifecycle-relay-callback-promises, gate-refactor-lifecycle-relay-channel-message-promise, gate-refactor-lifecycle-relay-reconnect-promise.
Scope-promote via /agile-workflow:scope when wanted.
