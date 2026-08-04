---
id: story-canonical-transcript-timestamp-ownership-app-consume-cleanup
kind: story
stage: implementing
tags: [app, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: [story-canonical-transcript-timestamp-ownership-extension-producer-ts, story-canonical-transcript-timestamp-ownership-error-frame-ts]
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# App consume + fallback cleanup (close the app-side residuals)

Unit D of `feature-canonical-transcript-timestamp-ownership`. Now that every
producer carries server `ts` (Units A–C), close the app-side residuals so no
authoritative event stamps `DateTime.now()` when the wire carries `ts`.

## Change (`app/lib/data/sync/sync_service.dart`)

- Buffered tool fallback narration: derive ONE `requestTs` from the wire `ts`
  (legacy `DateTime.now()` fallback) and use it for BOTH the fallback
  `AssistantMessageCommitted` and the `ToolRequested` — not an independent
  `DateTime.now()` for the narration.
- Sweep every authoritative producer (`UserMessageConfirmed`,
  `AssistantMessageCommitted`, `ToolRequested`/`ToolFinished`,
  `CompactionRecorded`, error diagnostic): confirm it consumes wire `ts`;
  `DateTime.now()` ONLY for genuinely-missing fields.

## Acceptance

- [ ] No authoritative app event stamps `DateTime.now()` when the wire carries
  `ts` (producer-connected app tests asserting real wire-`ts` flow, not injected).
- [ ] The (updated) enumeration table shows ZERO remaining authoritative
  phone-`ts` paths — the single-clock invariant finally holds.
- [ ] `flutter test --exclude-tags e2e test/domain test/data test/ui/chat`
  green; the 3 `streaming`-convergence guards green; `flutter analyze` clean.

## Ordering

`depends_on: [extension-producer-ts, error-frame-ts]` (needs all producers
carrying server `ts`). This is the closing unit of the feature.
