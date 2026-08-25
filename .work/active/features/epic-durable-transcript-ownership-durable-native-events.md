---
id: epic-durable-transcript-ownership-durable-native-events
kind: feature
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# F3 — Durable-ize Outpost-Pi-specific transcript events

## Brief

Mesh tool cards, compaction markers, tool-request-as-distinct-from-result,
steering events — currently in-memory only, lost on restart — become durable
via F1's codec. Ground-truth gap table:
`story-canonical-transcript-ordering-systematic-ts-provenance-sweep` (its
completed enumeration is absorbed into this design and the story is closed).

## Epic context

Consumer of F1's codec + append path. Independent of F2 (parallelizable).

## Simplification opportunity

Deletes the in-memory-only event kinds entirely; no dual representation.

## Native-event enumeration

The emission-path sweep covers every Outpost-Pi-specific event named by the
brief and reconciles it with the provenance table:

| Native fact | Current emission path | Current authority | F3 migration |
|---|---|---|---|
| Ordinary tool request | `pi-extension/src/index.ts` `tool_execution_start` | `tool_requested` appended through the non-durable compatibility path; SDK assistant `toolCall` can re-derive it | Record the execution-hook fact through F1 before broadcasting. The durable fact suppresses the SDK-derived collision on reopen. |
| Ordinary tool result | `pi-extension/src/index.ts` `tool_execution_end` | `tool_finished` appended through the non-durable compatibility path; SDK `toolResult` can re-derive it | Record the execution-hook fact through F1 before broadcasting. Request and result stay distinct durable entries. |
| Mesh tool card pair | `pi-extension/src/index.ts` `_deliverMeshMessageToAgent` | App-facing `tool_request` + `tool_result`, but no transcript-log fact or SDK message fallback | After mesh admission, record separate `tool_requested` and `tool_finished` v1 entries before broadcasting the card pair. Pre-upgrade mesh cards cannot be recovered; mixed-era replay starts at the first durable card. |
| Compaction marker | `pi-extension/src/index.ts` `session_compact` | `compaction_recorded` appended in memory; raw SDK compaction is the reopen fallback | Persist the marker through F1 and derive its identity/time from `compactionEntry.timestamp` when valid so the matching raw SDK fact is suppressed during mixed-era reconciliation. |
| Accepted steering | `pi-extension/src/index.ts` `_confirmUserDelivery` with `shouldSteer` | In-memory `user_confirmed` carrying `streamingBehavior: "steer"`; SDK user-message fallback loses the behavior | Record only the steering branch durably in F3. Preserve `streaming_behavior` in history projection. Ordinary user-confirmation timestamp migration remains sibling F2's ownership. |

The sweep story's blocking mesh discovery is therefore covered: mesh cards are
confirmed authoritative, receive durable request/result facts here, and sibling
F2 owns their producer timestamp equality. Its other enumerated gaps
(user-confirmation timestamp ownership, producer `ts` omissions, error frames,
`agent_done`, and app consumption) remain precisely F2, not residual F3 work.

## Design decisions

- **Durability boundary**: Reuse F1's `TranscriptEventLog.record` and SDK
  `appendEntry`; do not add a second native-event store or codec. This preserves
  persistence-before-visibility and one v1 schema.
- **Failure behavior**: A native transcript fact that cannot be persisted does
  not become live authoritative transcript UI. Non-transcript lifecycle work
  still completes: mesh ingress remains admitted to the SDK and compaction
  working state still converges idle.
- **Mixed-era behavior**: Keep F1's SDK-derived fallback only where the SDK has a
  corresponding fact (ordinary tools, compaction, users). Mesh cards have no
  historical SDK representation, so no synthetic recovery is attempted.
- **F2 boundary**: F3 changes durable ownership only. It does not add schema
  timestamps, migrate app consumers, or take the ordinary user-confirmation
  path. Native producers reuse existing event timestamps; F2 may subsequently
  refine their single-clock sourcing without changing the durable contract.

## Architectural choice

Three approaches were considered. (1) Add new transcript variants such as
`mesh_card` and `steering_recorded`; this makes provenance explicit but creates
new app/wire projection arms for facts already represented canonically as tools
and confirmed users. (2) Persist opaque live server frames; this guarantees
byte replay but duplicates the canonical `TranscriptEvent` contract and couples
storage to wire evolution. (3) **Chosen:** persist the existing canonical
`tool_requested`, `tool_finished`, `compaction_recorded`, and `user_confirmed`
variants through F1, then project them through the existing history mapper. It
is the smallest design, keeps one source of truth, and lets mixed-era collision
rules already established by F1 continue to work.

The trickiest unit is mesh tool cards: unlike ordinary tools they have no SDK
fallback at all, and delivery to the coding agent must not depend on transcript
persistence. The implementation therefore admits/enqueues first, records two
canonical facts second, and broadcasts only the successfully authoritative
card facts.

## Implementation Units

### Unit 1: Durable native tool events
**Files**: `pi-extension/src/index.ts`,
`pi-extension/src/session/transcript_projection.test.ts`,
`pi-extension/src/extension.test.ts`
**Story**: `epic-durable-transcript-ownership-durable-native-events-tool-events`

```ts
function _recordDurableTranscriptEvent(event: TranscriptEvent): TranscriptRecordResult;

// tool_execution_start/end and admitted mesh cards
_sdkSessionProjection.recordDurableTranscriptEvent(event);
```

**Implementation notes**:
- Ordinary execution hooks replace only their compatibility append with durable
  record; existing wire payload and timestamp behavior remain intact.
- Mesh request/result use deterministic identities based on `mesh_${env.id}` and
  remain two events. If a duplicate is encountered, reuse the recorded
  timestamp rather than creating a competing fact.
- Do not suppress the SDK mesh handoff when transcript persistence fails.

**Acceptance criteria**:
- [x] Request and result each write one v1 custom entry before live broadcast.
- [x] Reopen projects the same request/result pair.
- [x] Mixed SDK/durable tool history retains pre-upgrade fallback and lets the
      durable collision win.

### Unit 2: Durable compaction marker
**Files**: `pi-extension/src/index.ts`,
`pi-extension/src/session/transcript_projection.ts`,
`pi-extension/src/session/transcript_projection.test.ts`,
`pi-extension/src/extension.test.ts`
**Story**: `epic-durable-transcript-ownership-durable-native-events-compaction`

```ts
function compactionTimestamp(entry: { timestamp?: unknown }, fallback: number): number;
```

**Implementation notes**:
- Parse a valid SDK ISO timestamp and otherwise use the hook clock.
- Build one deterministic event id from that timestamp, record durably, and
  broadcast only an authoritative marker.
- Always execute `compaction_done`, `turn_end`, and `working:false` convergence.

**Acceptance criteria**:
- [x] Reopen preserves summary, token count, timestamp, and replay frame.
- [x] Matching raw + durable compaction entries project once; unmatched
      pre-upgrade raw entries remain.
- [x] Persistence failure cannot strand working state.

### Unit 3: Durable steering event and replay equivalence
**Files**: `pi-extension/src/session/sdk_session_projection.ts`,
`pi-extension/src/session/transcript_projection.ts`,
`pi-extension/src/session/transcript_projection.test.ts`,
`pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-durable-transcript-ownership-durable-native-events-steering`

```ts
recordDurableTranscriptEvent(event: TranscriptEvent): TranscriptRecordResult;
```

**Implementation notes**:
- Concurrent F2 migrated the shared `_confirmUserDelivery` producer to the
  generic durable recorder for all accepted app input. F3 adds no competing
  steering-only persistence path; it verifies that the existing event carries
  `streamingBehavior: "steer"` through v1 and reopen.
- History projection carries `streaming_behavior` from durable confirmed users;
  legacy SDK users omit it naturally.

**Acceptance criteria**:
- [x] Accepted steering writes v1 and reopens with stable identity and behavior.
- [x] Live and replay projections both say `streaming_behavior: "steer"`.
- [x] A pre-upgrade SDK user plus a later durable steer both replay correctly.

## Implementation Order

1. Durable native tool events.
2. Durable compaction marker.
3. Durable steering event and replay equivalence.

## Simplification

- Retain the single F1 codec, persistence port, and history mapper; add no
  native-event registry or alternate store.
- Remove native producers from the transitional in-memory append path as each
  checkpoint lands.
- Leave F4's global removal of SDK re-derivation and transitional aliases out of
  scope.

## Testing

- Producer-connected Vitest assertions capture real `appendEntry` calls and
  live broadcasts, protecting persistence-before-visibility rather than merely
  testing synthetic events.
- Fresh-projection reopen tests feed captured v1 custom entries through
  `buildContextEntries()` and compare projected `session_history` frames.
- Mixed-era tests combine raw SDK entries with later durable entries, protecting
  fallback without inventing missing pre-upgrade mesh facts.
- Run `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
  after every story and once for the completed feature.

## Risks

- **Concurrent F2 edits**: F2 changes timestamp sourcing at the same producers.
  F3 keeps its edits limited to record-vs-fallback ownership and will reconcile
  against F2's landed calls if the branch moves.
- **Fail-closed visibility**: A disk failure can hide a mesh card from the app
  while the agent still receives it. This is intentional: showing a fact that
  cannot replay would reintroduce split authority. Existing diagnostics remain
  content-free.
- **Compaction timestamp shape**: SDK entries normally carry ISO timestamps. An
  invalid/missing value falls back to hook time; reopen still keeps the durable
  fact, but cannot semantically dedupe a malformed raw entry. Corrupt raw input
  remains a compatibility edge, not a reason to reject a valid durable event.

## Completion summary

- Native tool execution requests/results now cross F1's v1 durable boundary
  before owner visibility. Mesh `agent-network` cards are separate durable
  request/result facts; ordinary tools retain SDK fallback for mixed-era data.
- Compaction markers use the valid SDK entry timestamp as durable identity,
  reopen once over matching raw fallback, and converge working idle even when
  persistence fails.
- Steering is stored as durable `user_confirmed` with
  `streamingBehavior: "steer"`; history replay now preserves
  `streaming_behavior: "steer"` alongside stable text/id/timestamp.
- Concurrent F2 shared producer work was incorporated at its landed commits;
  F3's three child checkpoints are done without duplicating timestamp/schema/app
  responsibilities.
- Final verification from `pi-extension/`: `corepack pnpm typecheck`, all 59
  Vitest files (1082 passed, 3 skipped), and `corepack pnpm build` passed.
