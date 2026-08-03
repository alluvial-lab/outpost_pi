---
id: story-canonical-transcript-ordering-projection-render-sort
kind: story
stage: implementing
tags: [app, bug]
parent: feature-canonical-transcript-ordering
depends_on: [story-canonical-transcript-ordering-app-consume-tool-ts]
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Projection renders authoritative bubbles in canonical server-ts order

Unit 3 of `feature-canonical-transcript-ordering` — the fix for the observed
reorder, correct once Units 1+2 give every authoritative bubble a single-clock
server `ts`. This is the verified attempt-2 design from the source story's
forensic; it is only landed now that tools carry server `ts`.

## Change

`app/lib/domain/transcript/transcript_projection.dart`
`deriveTranscriptProjection`:

- Thread each authoritative message's event `ts` (ms) + an arrival index into
  `messageTs` / `messageArrival` during the pass — `appendAuthoritative(msg, ts)`
  and `upsertTool(tool, ts)` record them when a message id is first created.
- **Leave the arrival-order lifecycle pass byte-for-byte unchanged** —
  `turn`/`streaming`/`steering`/tool-merge still derive from arrival order.
- AFTER the pass, sort `authoritativeMessages` by `(ts, arrivalIndex)` before
  assembling `messages = [...authoritativeMessages, ...localTail]`.
- Tool sort key: `messageTs[toolCallId] = min(existing, ts)` on every tool
  upsert, so the bubble sorts by REQUEST time regardless of arrival order
  (backfill can deliver result-before-request).
- The existing prompt-before-reply fixup stays as a same-`ts` safety net.

## Acceptance

- [ ] Regression (user/assistant): live user(T)+assistant(T+100), then
  replay-backfill user(T+50)+assistant(T+60) → message ids
  `[cli_1, cli_2, msg_2, msg_1]` (canonical). Red without the sort.
- [ ] **Tool regression (new):** with the phone clock skewed ahead, a tool
  request/result carrying server `ts` lands BETWEEN its surrounding narrations,
  not after them; result-before-request backfill still sorts by request `ts`.
- [ ] No-lifecycle-regression guard: the 3 `streaming`-convergence tests in
  `test/data/sync/sync_service_test.dart` (compaction-live, compaction-replay,
  history-replay) stay GREEN.
- [ ] Full `app/` suite (`flutter test --exclude-tags e2e`) green; the broader
  domain/data/chat-UI sweep green; `flutter analyze` clean.
- [ ] Final cross-model review (`openai-codex/gpt-5.6-sol`) APPROVE before close.

## Ordering

`depends_on: [story-canonical-transcript-ordering-app-consume-tool-ts]`
(transitively Unit 1 — needs server `ts` on tools or the tool sort mixes
clocks, which is exactly the regression attempt 2 introduced).
