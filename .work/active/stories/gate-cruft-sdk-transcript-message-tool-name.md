---
id: gate-cruft-sdk-transcript-message-tool-name
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove the unused SDK transcript message tool-name field

## Confidence
High

## Category
Dead field / codec-reconciler residue

## Relevance
Release-relevant: introduced in the F4 live/reconciliation message shape.

## Location
`pi-extension/src/session/transcript_projection.ts:6-16` (`toolName` at line 12)

## Evidence
```ts
export type SdkTranscriptMessage = {
  role: "user" | "assistant" | "toolResult" | "compaction" | "compactionSummary" | string;
  content?: unknown;
  summary?: string;
  timestamp?: number;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
```

A repository-wide search finds no read of `toolName`; the reconciler uses `toolCallId`, `tool`, and `name` from assistant blocks instead.

## Removal rationale
Remove `toolName?: string` from `SdkTranscriptMessage`. Keep the runtime boundary permissive through the existing `unknown` content/role handling; no parser or SDK message is changed by deleting this type-only property.

## Risk
None to runtime behavior or wire/persistence contracts. The type is internal to the extension and has no verified external consumers.

## Implementation
- Proof: repository grep found `SdkTranscriptMessage.toolName` only at its declaration; other `toolName` occurrences belong to Pi SDK execution-hook events and do not consume this type property. Reconciliation reads `toolCallId`, while assistant tool names come from content-block `name`.
- Removal: deleted the type-only optional `toolName` property from `SdkTranscriptMessage`; runtime parsing and SDK values remain unchanged.
- Verification: `corepack pnpm typecheck` and the transcript projection/session projection suites passed (82 tests). The release-wide extension test/build suite is recorded in the gate-fix completion report.
- Execution capability: sol/high; direct-read cleanup with grep and compiler evidence.
- Adjacent issues parked: none.
