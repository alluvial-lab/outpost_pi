---
id: story-canonical-transcript-ordering-app-consume-tool-ts
kind: story
stage: implementing
tags: [app, bug]
parent: feature-canonical-transcript-ordering
depends_on: [story-canonical-transcript-ordering-extension-broadcast-tool-ts]
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# App consumes server ts on live tool frames

Unit 2 of `feature-canonical-transcript-ordering`. Once the extension broadcasts
`ts` (Unit 1), the app must use it instead of `DateTime.now()` when constructing
`ToolRequested`/`ToolFinished`, with a fallback for old-extension frames.

## Change

- `app/lib/protocol/generated/protocol.g.dart` — `ToolRequest`/`ToolResult`
  gain the optional `ts` field (generated from the schema in Unit 1).
- `app/lib/data/sync/sync_service.dart` — `case ToolRequest` (:1101) and
  `case ToolResult` (:1162):
  ```dart
  ts: ts != null
      ? DateTime.fromMillisecondsSinceEpoch(ts)
      : DateTime.now(),   // fallback for old extension / frame without ts
  ```

## Acceptance

- [ ] A live `tool_request` with `ts` yields a `ToolRequested` carrying that
  server `ts` (assert equal, not `DateTime.now()`).
- [ ] A `tool_result` with `ts` yields a `ToolFinished` carrying that server
  `ts`.
- [ ] Frames without `ts` fall back to `DateTime.now()` (no regression for old
  extension) — explicit test.
- [ ] `flutter test --exclude-tags e2e` green; `flutter analyze` clean.

## Ordering

`depends_on: [story-canonical-transcript-ordering-extension-broadcast-tool-ts]`
(needs the wire field + regenerated DTO). Unblocks
`story-canonical-transcript-ordering-projection-render-sort`.
