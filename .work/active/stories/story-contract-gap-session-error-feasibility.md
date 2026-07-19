---
id: story-contract-gap-session-error-feasibility
kind: story
stage: implementing
tags: [pi-extension, app, docs]
parent: feature-contract-gap-audit
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-19
---

# Determine whether session lineage can support typed mismatch errors

## Checkpoint

Complete Track B as a feasibility spike, not a wire-design pass. Trace the
installed Pi SDK's session lineage exposed to `ExtensionContext`, the
Outpost-Pi `session_new` call, and relay fanout. Then verify that the already
shipped app-side behavior protects both required cases:

1. a mismatch response from a foreign/duplicate Pi does not render an error;
2. a canonical room-metadata session rotation still triggers `session_sync`.

## Acceptance evidence

- [ ] State whether the current extension can reliably classify a received
      `session_id` as the predecessor of its active session.
- [ ] State whether that classification would distinguish cross-process
      duplicate fanout.
- [ ] Cite the tests protecting foreign-error suppression and legitimate
      stale-session resync.
- [ ] Do not add `session_superseded` / `not_my_session` wire codes unless both
      cases are distinguishable at the extension boundary.
