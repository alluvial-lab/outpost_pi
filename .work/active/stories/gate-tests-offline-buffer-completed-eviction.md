---
id: gate-tests-offline-buffer-completed-eviction
kind: story
stage: done
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Prove completed-buffer eviction preserves a current interval that still fits

## Priority
High

## Value evidence
Item: `feature-outbound-buffer-on-peer-offline-bounded-turn-buffer`

Contract / risk / regression / maintenance cost: the release contract requires cap pressure to evict the older completed interval and retry before sacrificing the current interval (`.work/active/features/feature-outbound-buffer-on-peer-offline.md:123-125`; `.work/active/stories/feature-outbound-buffer-on-peer-offline-bounded-turn-buffer.md:33-36`). The current frame-cap test at `pi-extension/src/extension/owner_multiplexer.test.ts:187-203` continues until the current interval itself overflows, so its final assertion proves whole-current discard and post-boundary recovery but cannot distinguish completed-first eviction from prematurely discarding both intervals. The byte-cap test at `pi-extension/src/extension/owner_multiplexer.test.ts:206-225` likewise starts with an oversized current frame and never exercises the retry-success branch. A regression in the core overflow ordering could therefore discard a coherent current turn unnecessarily while both tests remain green.

## Gap type
complex-unit / boundary — missing decision-table case where completed + current exceeds a cap but current alone remains within it.

## Suggested test
```ts
test("cap pressure evicts the completed interval before preserving a fitting current interval", () => {
  // Buffer and complete an older interval.
  // Add a current interval whose combined size/count crosses one hard cap,
  // while the current interval alone remains within that cap.
  // Resume and assert only the complete current interval flushes in FIFO order;
  // no older frame and no partial-current loss is observed.
});
```

## Test location (suggested)
`pi-extension/src/extension/owner_multiplexer.test.ts`

## Implementation notes

- **Execution capability:** inline, focused test-only implementation because the
  gap is a deterministic complex-unit boundary case with one owning test file.
- **Files changed:** `pi-extension/src/extension/owner_multiplexer.test.ts`.
- **Test added:** buffers one completed frame, then admits exactly 2,048 current
  frames. The final current admission crosses the combined frame cap while the
  current interval alone still fits; reconnect must flush exactly those current
  frames in FIFO order, proving completed-first eviction without partial-current
  loss.
- **Confirmation:** focused test file passed (17 tests); `corepack pnpm
  typecheck` passed; full `corepack pnpm test` passed (52 files, 881 passed, 3
  skipped). The reported behavior was already correct, so the finding required
  regression coverage rather than a production-code repair.
- **Bounded inline review:** pass. The setup necessarily enters the
  completed-plus-current cap-pressure branch, and exact-array equality rejects
  both stale completed output and any missing/reordered current frame.
- **Adjacent issues parked:** none.
