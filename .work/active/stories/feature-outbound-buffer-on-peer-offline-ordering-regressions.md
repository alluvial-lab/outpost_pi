---
id: feature-outbound-buffer-on-peer-offline-ordering-regressions
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: [feature-outbound-buffer-on-peer-offline-presence-lifecycle, feature-outbound-buffer-on-peer-offline-turn-boundary-wiring]
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
---

# Outbound buffer ordering and lifecycle regressions

## Brief

Implement Unit 4 from `feature-outbound-buffer-on-peer-offline`: update the
existing suspend/resume expectation and add focused deterministic evidence for
overflow atomicity, reconnect ordering, teardown, and separation from the
online and late-attach paths.

## Files

- `pi-extension/src/extension/owner_multiplexer.test.ts`
- `pi-extension/src/extension.test.ts`

## Acceptance criteria

- [x] The existing suspend/resume test expects the formerly dropped frame to
      flush before the next live frame.
- [x] Frame-count and byte-cap tests prove whole-interval discard and recovery
      after the next turn boundary.
- [x] Detach and same-peer reattach tests prove old frames cannot leak into the
      replacement channel.
- [x] Integration coverage exercises both races: `peer_online` first yields an
      atomic FIFO before later idempotent history; `session_sync` first yields
      history with no later stale FIFO flush.
- [x] Existing online multi-owner and active-turn late-attach semantics remain
      green and do not double-deliver through the offline buffer.

## Implementation

Updated suspend/resume to require FIFO flush before live delivery and added
deterministic coverage for re-entrant flush ordering, both hard caps, cyclic
serialization failure, completed-turn replacement, send-failure convergence,
sync-first arbitration, detach/relay-drop/reattach cleanup, and late-attach
separation. Integration coverage drives real relay control and owner ingress
for both reconnect orderings and proves normal plus synthetic compaction
`turn_end` boundaries retain exactly the newest completed interval and active
suffix.

Verification: `./node_modules/.bin/tsc --noEmit`; targeted owner multiplexer and
reconnect/boundary integration Vitest (17 passed).
