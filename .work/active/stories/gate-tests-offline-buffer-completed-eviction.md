---
id: gate-tests-offline-buffer-completed-eviction
kind: story
stage: implementing
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
