---
id: gate-refactor-v0.13.0-wake-timer-shutdown
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: refactor
created: 2026-10-05
updated: 2026-10-05
---

# gate-refactor v0.13.0: deferred wake timer survives shutdown

scan-lifecycle `resource-no-dispose` violation (verified): `shutdown()`
cancelled `_lockRetryTimer` but left the deferred wake timer armed — its
callback could fire a channel notification during/after teardown (`unref()`
prevents holding the process open, never cancels the callback), and a mesh
message arriving during `mesh.close()` could arm a fresh timer post-cancel.

Fixed in-gate: shutdown clears the deferred wake timer synchronously;
`onMessage` returns early once `_shuttingDown` (no post-boundary wake
scheduling). Typecheck + targeted 28 + build green.

All other loaded rules (boundaries, protocol-contract, Flutter async
guards, working convergence, unguarded async-void, single-source limits)
reported clean over the bundle's changed files.
