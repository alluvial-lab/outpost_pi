---
id: gate-tests-offline-buffer-per-peer-isolation
kind: story
stage: review
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-20
updated: 2026-07-28
---

# Cover independent buffering and cap accounting for simultaneous offline owners

## Priority
Medium

## Value evidence
Item: `feature-outbound-buffer-on-peer-offline`

Contract / risk / regression / maintenance cost: multi-owner isolation is explicit release behavior: each offline peer must have an independent FIFO and independent cap accounting (`.work/active/features/feature-outbound-buffer-on-peer-offline.md:178-182`; `.work/active/stories/feature-outbound-buffer-on-peer-offline-bounded-turn-buffer.md:29-36`). Existing multi-owner coverage at `pi-extension/src/extension/owner_multiplexer.test.ts:130-148` keeps only owner A offline while owner B remains online; all cap and overflow cases at `pi-extension/src/extension/owner_multiplexer.test.ts:172-225` use only owner A. No test places two owners offline simultaneously or proves overflow/turn completion for one cannot evict, suppress, reorder, or flush the other's FIFO.

## Gap type
complex-unit / state transition — missing per-key isolation coverage across simultaneous offline buffers and independent resume.

## Suggested test
```ts
test("simultaneous offline owners keep independent buffers and overflow state", () => {
  // Mark owners A and B offline and buffer distinct frames for both.
  // Overflow or complete a turn for A only, then resume B and assert B's FIFO
  // is intact. Resume A separately and assert only A's documented retained
  // interval is delivered, with neither owner's frames crossing recipients.
});
```

## Test location (suggested)
`pi-extension/src/extension/owner_multiplexer.test.ts`

## Implementation notes

- Added a simultaneous-offline-owner regression: owner A has an older completed
  interval, then both owners buffer a frame-cap current interval. A's combined
  cap evicts only A's older interval; B's independent FIFO remains intact and
  flushes before A resumes.
- Changed `pi-extension/src/extension/owner_multiplexer.test.ts` only.
- Verified with `vitest run src/extension/owner_multiplexer.test.ts` (30 tests)
  and `tsc --noEmit`.
