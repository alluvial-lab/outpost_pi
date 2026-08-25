---
id: epic-durable-transcript-ownership-durable-event-log
kind: feature
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-26
---

# F1 — Durable transcript event log (foundation)

## Brief

The extension becomes the authoritative owner of its transcript event log:
custom-entry codec `outpost-pi.transcript-event.v1`, `appendEntry` binding,
`TranscriptEventLog` becomes durable, backfill from `buildContextEntries()`
preferring validated Outpost-Pi events over SDK-derived projection. This is
the epic's architectural foundation — F2/F3/F4 all depend on it.

## Epic context

- Parent: `epic-durable-transcript-ownership` — foundation feature; everything
  else consumes its types and persistence.
- Seed material: the spike verdict + Unit-A design live in
  `story-canonical-transcript-timestamp-ownership-ownership-foundation`
  (read-only spike DONE — feasibility proven; the durable implementation is
  THIS feature's work). Absorb that story's design into the feature-design
  pass and close it as the spike.

## Key constraints from the spike

- Assistant `message_end` fires before `tool_execution_start` → execution ts
  cannot retrofit into SDK-persisted messages → custom-entry path (not reuse).
- `appendEntry` → `SessionManager.appendCustomEntry` → session JSONL →
  recoverable via compaction-aware `buildContextEntries()`.
- SDK messages stay authoritative for LLM context; extension entries for
  transcript.

## Simplification opportunity

Retires the in-memory `TranscriptEventLog` rebuild path once backfill prefers
durable entries — the lossy re-derivation becomes fallback-only (F4 deletes it).

## Grounding record

Direct-read only: the feature is bounded to the transcript aggregate, SDK
session adapter, and existing restart harness. The design was checked against
`transcript_event.ts`, `transcript_event_log.ts`, `transcript_projection.ts`,
`sdk_session_projection.ts`, the installed 0.80.6 SDK declarations/runtime, and
both resume-backfill test layers. The SDK facts from the completed spike hold:
`ExtensionAPI.appendEntry(customType, data)` synchronously delegates to
`SessionManager.appendCustomEntry`; `ReadonlySessionManager.buildContextEntries()`
returns the active compaction-aware entry branch; plain custom entries are
excluded from `buildSessionContext()` and therefore never enter LLM context.
Independent design advisory was not dispatched because this execution was
explicitly host-side only; the completed SDK spike supplies the external API
evidence for the riskiest unit.

## Design decisions

- **Durability boundary:** `TranscriptEventLog` owns a narrow injected
  persistence port; `SdkSessionProjection` adapts the current session's
  `appendEntry` capability to it. The log remains independent of the Pi SDK,
  while persistence-before-visibility and dedupe live in one aggregate.
- **Version location:** `outpost-pi.transcript-event.v1` is the only v1 marker;
  the payload is the canonical event, without a second version field that could
  disagree with the custom type.
- **Write policy:** durable recording is fail-closed. A duplicate is a no-op;
  a missing/stale/throwing writer does not install an in-memory authoritative
  event. Producer migrations in F2/F3 must inspect the record result before
  broadcasting. Existing F1-era producers stay on an explicitly named
  fallback append path until those features migrate them.
- **Backfill authority:** valid v1 events suppress only their semantically
  matching SDK-derived transcript facts. Invalid/unknown custom entries never
  suppress the SDK fallback. SDK messages remain untouched and authoritative
  for LLM context.
- **Mixed-session migration:** no rewrite or one-time migration. Pre-upgrade
  SDK-only history continues through the existing lossy projection; valid v1
  entries written after upgrade win for matching facts in the same session.
- **Fork/rehome behavior:** a decoded durable event is hydrated under the
  current SDK session id while retaining its stable event id. This keeps copied
  history visible after SDK fork without inventing a second semantic identity;
  live events in the fork use the new session's deterministic ids.
- **Foundation-doc timing:** code-first. `docs/ARCHITECTURE.md` already states
  append-only transcript/event replay semantics and does not contradict this
  design; implementation should roll it forward only if the resulting durable
  ownership needs an explicit standing assertion.

## Architectural choice

### Chosen: log-owned persistence port with SDK adapter

`TranscriptEventLog` receives a tiny synchronous `TranscriptEventPersistence`
port. Its durable `record` operation validates/encodes through the v1 codec,
calls persistence, and only then installs the event in the first-writer-wins
index. `SdkSessionProjection` binds a lifecycle-fresh adapter that invokes
`appendEntry`. Hydration and the legacy fallback are separate methods that do
not persist again. This keeps the aggregate's invariant in one place while
isolating SDK staleness and session-tree reading at the adapter boundary.

### Rejected: projection-owned dual write

`SdkSessionProjection` could call `appendEntry` and then separately call the
current in-memory log. It is initially smaller, but every producer can get the
ordering, duplicate, and failure behavior wrong independently—the same implicit
ownership class this epic exists to remove.

### Rejected: a separate Outpost-Pi JSONL file

A standalone file could provide full write control, but would create a third
session identity/tree, duplicate branch/compaction behavior, and require its own
atomicity/cleanup rules. The SDK custom-entry API already supplies the correct
session lifecycle and active-branch semantics.

## Implementation Units

### Unit 1: Versioned codec and durable aggregate contract

**Files**:
- `pi-extension/src/session/transcript_event.ts`
- `pi-extension/src/session/durable_transcript_event.ts` (new)
- `pi-extension/src/session/durable_transcript_event.test.ts` (new)
- `pi-extension/src/session/transcript_event_log.ts`
- `pi-extension/src/session/transcript_event_log.test.ts` (new)

**Story**: `epic-durable-transcript-ownership-durable-event-log-codec-and-log`

```ts
import type { JsonValue } from "../protocol/generated/protocol.generated.js";

export const TRANSCRIPT_EVENT_CUSTOM_TYPE =
  "outpost-pi.transcript-event.v1" as const;
export const TRANSCRIPT_EVENT_CUSTOM_TYPE_PREFIX =
  "outpost-pi.transcript-event.v" as const;

export type DurableTranscriptEventDecode =
  | { status: "decoded"; event: TranscriptEvent }
  | { status: "not_transcript" }
  | { status: "unsupported_version" }
  | { status: "invalid" };

export function encodeDurableTranscriptEventV1(
  event: TranscriptEvent,
): JsonValue;

export function decodeDurableTranscriptEntry(
  entry: unknown,
): DurableTranscriptEventDecode;

export interface TranscriptEventPersistence {
  append(event: TranscriptEvent): void;
}

export type TranscriptRecordResult =
  | { status: "recorded" }
  | { status: "duplicate" }
  | { status: "unavailable" }
  | { status: "failed" };

export class TranscriptEventLog {
  bindPersistence(persistence: TranscriptEventPersistence): void;
  unbindPersistence(persistence?: TranscriptEventPersistence): void;
  record(event: TranscriptEvent): TranscriptRecordResult;
  appendFallback(event: TranscriptEvent): boolean;
  hydrate(events: readonly TranscriptEvent[]): number;
  recordedTsFor(eventId: string): number | undefined;
  replace(events: readonly TranscriptEvent[]): void;
  clear(): void;
  forSession(sessionId: string): readonly TranscriptEvent[];
  entries(): readonly TranscriptEvent[];
}
```

**Codec schema and validation**:

- The SDK entry must be an object with `type: "custom"`, exact
  `customType: "outpost-pi.transcript-event.v1"`, and a `data` object.
- `data` is one v1 `TranscriptEvent`: exact non-empty `kind`, `eventId`, and
  `sessionId`; finite non-negative safe-integer `ts`; optional non-empty
  `turnId`; then exactly the fields allowed by that discriminated-union arm.
- Stable identifiers (`clientMessageId`, `messageId`, `replyTo`,
  `toolCallId`) and required names/text are strings. Images require exact
  `{data, mime}` objects. Usage requires finite non-negative token counts.
  Tool args and result payloads must be recursively JSON-safe; cyclic values,
  bigint, functions, symbols, non-finite numbers, and unexpected properties
  fail encoding rather than relying on `JSON.stringify` surprises.
- Reuse the schema-generated `JsonValue`; do not introduce another JSON-value
  union. All current event kinds are schema-owned in `transcript_event.ts`; the
  runtime validator is exhaustive over that registry/union and uses an
  `assertNever` check so type changes force codec review. Unknown kinds are
  invalid to a v1 reader. An unknown `outpost-pi.transcript-event.vN` custom
  type is `unsupported_version`, while unrelated custom entries are
  `not_transcript`.
- `record` checks the event-id index before persistence, calls the port
  synchronously, and installs the event/index/timestamp only on return.
  `appendFallback` and `hydrate` reuse the same first-writer-wins install helper
  but never call persistence. `clear`/`replace` rebuild both event and timestamp
  indexes.

**Acceptance Criteria**:

- [ ] Representative user, assistant, tool, error, and compaction events
  round-trip exactly through v1; malformed/unknown/non-JSON-safe data cannot
  enter the log through the durable path.
- [ ] Duplicate durable records call persistence once and preserve the first
  event/`ts`; `recordedTsFor` tracks `appendFallback`, `hydrate`, `replace`, and
  `clear` consistently.
- [ ] Persistence unavailable/failure is observable in the result and does not
  create a locally authoritative event.

---

### Unit 2: Lifecycle-fresh appendEntry binding

**Files**:
- `pi-extension/src/session/sdk_session_projection.ts`
- `pi-extension/src/session/sdk_session_projection.test.ts`

**Story**: `epic-durable-transcript-ownership-durable-event-log-sdk-binding`

```ts
export type TranscriptEntryApi = Pick<ExtensionAPI, "appendEntry">;

export function isTranscriptEntryApi(value: unknown): value is TranscriptEntryApi;

export class SdkSessionProjection {
  recordDurableTranscriptEvent(event: TranscriptEvent): TranscriptRecordResult;
  appendFallbackTranscriptEvent(event: TranscriptEvent): boolean;
  recordedTranscriptTs(eventId: string): number | undefined;
}
```

**Implementation Notes**:

- Keep `AgentMessageApi` and `TranscriptEntryApi` separate: a context can carry
  one capability without the other. `bindApi`/`bindCapabilities` installs the
  append adapter when `appendEntry` exists. `clearStaleContexts`, replacement,
  and stale-capability handling unbind only the matching writer; a later fresh
  binding restores it.
- The adapter calls
  `api.appendEntry(TRANSCRIPT_EVENT_CUSTOM_TYPE,
  encodeDurableTranscriptEventV1(event))`. It does not call
  `SessionManager.appendCustomEntry` directly; production remains on the public
  SDK API verified by the spike.
- Keep `appendTranscriptEvent` as a compatibility wrapper only if call-site
  churn would obscure F1; it must delegate to the explicitly named fallback
  path and carry a removal note for F4. Do not silently switch existing
  `message_end`, tool, compaction, mesh, or error producers to durable recording
  in F1: F2/F3 own those semantic migrations.
- A stale SDK throw is classified as a failed record and evicts the matching
  persistence adapter. Other throws also fail the record; diagnostics expose a
  bounded category only, not event payload/error text.

**Acceptance Criteria**:

- [ ] A bound fake API receives one exact v1 custom entry before the same event
  appears in memory; missing/throwing/stale APIs produce no authoritative
  in-memory append.
- [ ] Session shutdown/replacement cannot retain a stale append capability, and
  a new binding records successfully.
- [ ] F1 does not change which existing producer event kinds are durable; it
  establishes the path consumed by F2/F3.

---

### Unit 3: Compaction-aware reconciliation and real reopen evidence

**Files**:
- `pi-extension/src/session/transcript_projection.ts`
- `pi-extension/src/session/sdk_session_projection.ts`
- `pi-extension/src/session/sdk_session_projection.test.ts`
- `pi-extension/test/support/sdk_session_replacement_harness.ts`
- `pi-extension/test/sdk-session-replacement.test.ts`

**Story**: `epic-durable-transcript-ownership-durable-event-log-backfill-reopen`

```ts
export type SdkTranscriptContextEntry =
  | { type: "message"; message: LegacyAgentMessage }
  | {
      type: "compaction";
      summary: string;
      tokensBefore: number;
      timestamp: string;
    }
  | { type: "custom"; customType: string; data?: unknown }
  | { type: string };

export function mapSdkContextEntriesToTranscriptEvents(input: {
  sessionId: string;
  entries: readonly SdkTranscriptContextEntry[];
}): TranscriptEvent[];
```

**Reconciliation flow**:

1. Capture `ctx.sessionManager.buildContextEntries()` once after the fresh
   session id is captured. Never use `getEntries()` (inactive branches) or
   mutate the SDK context source.
2. First pass: decode all valid v1 custom entries, rehome each event's
   `sessionId` to the current SDK session id, preserve entry order/event id,
   first-writer-wins duplicate identity, and pre-index semantic collisions.
   Tool collisions key by `(kind, toolCallId)`; ordinary deterministic events
   key by `eventId`; app-origin users use FIFO queues by the existing
   text+images content signature so repeated identical prompts reconcile one
   for one rather than all collapsing.
3. Second pass in SDK entry order: append decoded durable events at their custom
   entry position. Map message entries with the existing legacy adapter, but
   suppress only projections claimed by a valid durable collision. An assistant
   SDK message may therefore contribute text while its tool-call blocks are
   suppressed in favor of later per-call execution entries—the binding
   `message_end`-before-`tool_execution_start` ordering.
4. Map raw SDK compaction entries directly to `compaction_recorded`, converting
   the SDK entry's ISO `timestamp` to epoch milliseconds (invalid dates fall
   back to `0` like the legacy adapter); preserve the existing
   `compactionSummary` fallback only where tests/legacy fixtures still enter
   through `buildSessionContext`. Unknown SDK entry types remain irrelevant to
   transcript projection.
5. Hydrate the resulting list without writing custom entries again, then
   recompute `lastTranscriptUserId`. If `buildContextEntries` is absent/throws,
   keep session start non-fatal and return no backfill, matching current
   lifecycle posture.

**Acceptance Criteria**:

- [ ] A valid durable tool request with execution `ts=S` wins over an earlier
  assistant tool-call projection with SDK `ts=A`; a valid durable finish with
  `ts=E` wins over SDK tool-result `ts=R`; assistant text remains SDK-derived.
- [ ] Two tool calls in one assistant message retain two independent durable
  request events and ordering.
- [ ] Valid durable app-user identity wins one-for-one over its SDK-derived
  synthetic identity, including repeated equal-content prompts.
- [ ] Corrupt v1 and unsupported-version entries are ignored and cannot suppress
  the SDK fallback; unrelated custom entries are untouched.
- [ ] Resume/reload remains idempotent, compaction only hydrates the active
  branch, and `/new` still clears prior transcript state.

## Implementation Order

1. `epic-durable-transcript-ownership-durable-event-log-codec-and-log`
2. `epic-durable-transcript-ownership-durable-event-log-sdk-binding` — depends
   on 1.
3. `epic-durable-transcript-ownership-durable-event-log-backfill-reopen` —
   depends on 2.

The feature stays one cohesive implementation/review bundle; the stories are
ordered design checkpoints, not separate worker assignments.

## Simplification

- Replace ad-hoc backfill mutation in `SdkSessionProjection` with one pure
  context-entry-to-event mapper plus `TranscriptEventLog.hydrate`.
- Consolidate `seen` and timestamp ownership into one event-id index instead of
  parallel scans/sets.
- Retain `mapLegacyAgentMessagesToTranscriptEvents` and the named fallback in
  F1 because real pre-durable sessions still depend on them. F4—not this
  feature—deletes that lossy path after F2/F3 complete durable coverage.
- Do not add a second file/database, a retry queue, or a generic schema library.

## Testing

- **Codec boundary (`durable_transcript_event.test.ts`)**: table-driven
  representative round trips plus malformed common fields, wrong arm fields,
  unknown kind/version, and non-JSON-safe nested values. This protects durable
  format acceptance without testing every trivial optional-field permutation.
- **Aggregate interface (`transcript_event_log.test.ts`)**: persistence-before-
  visibility, duplicate/no-second-write, failure/unavailable behavior,
  recorded-ts indexing, hydrate-no-repersist, and clear/replace rebuild.
- **Projection regression (`sdk_session_projection.test.ts`)**: update the fake
  resumed context to expose `buildContextEntries`; test valid-over-SDK
  preference, repeated user FIFO, corrupt/unknown fallback, compaction, reload
  idempotence, and stale writer eviction at stable projection boundaries.
- **File-backed reopen (`test/sdk-session-replacement.test.ts`)**: use a real
  temp `SessionManager`, an `appendEntry` adapter, `SessionManager.open`, and a
  fresh `SdkSessionReplacementHarness` to assert `session_sync` preserves the
  exact durable identities/timestamps. Extend the harness's fake SDK action so
  `appendEntry` delegates to that instance's real
  `sessionManager.appendCustomEntry` instead of a no-op.
- **Partial write**: append a deliberately truncated final custom-entry JSONL
  line to a valid temp session, reopen through the SDK (whose parser skips
  malformed lines), and assert valid-prefix SDK fallback history remains. Do
  not emulate corruption by bypassing the actual file parser.
- Preserve existing restart-backfill and session-replacement tests; rename
  assertions/comments from `buildSessionContext` to `buildContextEntries` where
  the production contract changes. No tests are obsolete enough to remove in
  F1.

Implementation verification: from `pi-extension/`, run targeted codec/log/
projection/replacement Vitest files first, then `corepack pnpm typecheck`,
`corepack pnpm test`, and `corepack pnpm build` with the documented repo-local
cache environment.

## Migration and failure behavior

- **Pre-upgrade and in-flight sessions:** the first process running F1 reads
  SDK-only history through fallback. New valid custom entries can coexist with
  that prefix; no bulk copy is attempted. Extension-only facts already lost
  before upgrade cannot be reconstructed and are not fabricated.
- **Corrupt v1 payload:** ignore that custom entry, do not suppress a matching
  SDK projection, continue session start. A custom-only fact may be absent, but
  valid history is never discarded because malformed data claimed authority.
- **Unknown version:** classify and ignore. Never parse a future version as v1;
  leave SDK fallback available.
- **Partial final write:** rely on the SDK JSONL parser's malformed-line skip and
  hydrate the valid active prefix. No extension-level file repair or truncation.
- **Append failure/stale API:** return failed/unavailable, evict stale ownership,
  and do not expose a locally authoritative event. F2/F3 producers must avoid
  broadcasting the event as durable success and may surface a bounded
  persistence diagnostic.
- **Compaction/branching:** only `buildContextEntries()` defines active history.
  Custom entries omitted by compaction or an inactive branch are not resurrected
  from `getEntries()`.

## Risks

- **SDK write failure is not transactional.** `SessionManager` updates its
  in-memory tree before its synchronous file append. If the filesystem throws,
  `appendEntry` cannot tell the extension whether bytes were partially written.
  Fail-closed recording plus real partial-line reopen coverage avoids claiming
  durability, but the extension cannot repair an SDK-owned broken parent chain.
- **Reconciliation must look ahead.** Assistant `message_end` precedes tool
  execution, so an SDK-derived tool request appears before its authoritative
  custom entry. A one-pass first-writer-wins replay would preserve the wrong
  timestamp; the durable collision pre-index is mandatory.
- **Repeated identical user prompts need cardinality, not a set.** Content-only
  suppression would collapse legitimate repeats. FIFO queues preserve one-for-
  one matching; file-backed tests pin it.
- **Forked sessions copy payload session ids.** Rehoming only `sessionId` while
  retaining stable event ids is intentional; rejecting the old embedded id
  would blank otherwise-valid fork history. Test this when the harness exposes
  a low-cost fork fixture; reopen/resume is the required F1 evidence.
- **Codec expansion can drift from `TranscriptEvent`.** Keep the kind registry,
  static union, and exhaustive runtime validator co-located; a new event kind
  must fail typecheck or codec tests until its persistence policy is decided.

## Pre-mortem

The riskiest production failure is a superficially successful restart that
quietly chooses the earlier SDK tool-call timestamp because the durable entry
appears later in the active branch. The design counters this with a two-pass
collision index and a real multi-tool reopen test. If the installed SDK's
file-backed behavior differs from the spike, the fallback remains the current
SDK projection and F2/F3 stay blocked from producer migration; do not delete or
weaken the fallback in F1.

## Implementation summary

- **Durable now:** canonical transcript events have a strict versioned custom-entry codec; `TranscriptEventLog.record` persists synchronously through the lifecycle-fresh public SDK `appendEntry` capability before installing in-memory authority; reopen reads the active compaction-aware entry branch and prefers validated durable user/tool facts with stable identities and execution timestamps.
- **Still fallback:** all pre-upgrade SDK-only history and existing F1-era `message_end`, tool, compaction, mesh, and error producers continue through the explicitly named lossy SDK-message fallback. F2/F3 migrate those producers deliberately, and F4 retires re-derivation only after durable coverage is complete.
- **Invariants held:** SDK messages are neither mutated nor replaced and remain authoritative for LLM context; plain custom entries remain excluded from `buildSessionContext`; extension entries are authoritative only for matching transcript facts; invalid, future-version, and partial writes cannot suppress valid SDK fallback; first-writer event identity, FIFO repeated-user cardinality, fork rehoming, active-branch compaction, and fail-closed append ownership are covered by focused and file-backed tests.
- **Verification:** final targeted codec/projection/replacement run passed 108 tests; pi-extension typecheck, full 59-file suite (1076 passed, 3 skipped), and build passed.

## Completion (2026-08-25)
All 3 child stories done (aa6b52bb, ad030bc8, 40732a78). 1076 tests green.
Durable transcript ownership is live: v1 codec, lifecycle-fresh appendEntry
binding, two-pass compaction-aware reconciliation with FIFO/fork matching,
real-file reopen coverage. Legacy re-derivation retained as fallback for F4.

## Epic review closure (2026-08-26)

- Fork hydration now keys in-memory identity by `(sessionId, eventId)`, so copied
  durable facts remain independently addressable in parent and fork. Rehomed
  assistant and compaction facts also suppress their fork-local SDK fallbacks by
  semantic identity. A real `AgentSessionRuntime.fork`/switch/reopen test proves
  complete parent and fork user/assistant/tool histories in one process.
- Equal-content durable user claims bind to the nearest preceding SDK user fact,
  preserving identical legacy prefixes (including a compaction-kept variant)
  while the current durable event remains authoritative exactly once.
- JSON cloning defines own properties explicitly, preserving a valid
  `__proto__` tool-args key across encode/decode without prototype mutation.
