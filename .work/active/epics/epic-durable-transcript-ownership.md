---
id: epic-durable-transcript-ownership
kind: epic
stage: done
tags: [pi-extension, app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
---

# Durable transcript ownership (the extension owns its transcript event log)

## The architectural shift

Today the extension's transcript is a **lossy re-derivation from SDK messages**.
`TranscriptEventLog` (`pi-extension/src/session/transcript_event_log.ts`) is
purely in-memory; on every Pi process restart it is rebuilt by projecting the
SDK's durable messages. The extension persists **nothing** of its own (it does
not use the SDK custom-entry API anywhere today — confirmed).

That re-derivation is the root of an entire **divergence class**: the extension's
live events (execution/delivery-hook `ts`, outpost-pi-specific events the SDK
doesn't model) and the SDK's durable messages (SDK-persisted `ts`) are two
different sources of truth, and restart backfill silently picks the SDK's. It
has burned four review rounds (deltas → tools → tool-history divergence +
fallback narration + agent_done producer + error diagnostics) and a systematic
enumeration (see
`story-canonical-transcript-ordering-systematic-ts-provenance-sweep`) before we
stopped patching instances and named the class.

This epic makes the **extension the authoritative owner of its own durable
transcript event log**, persisted alongside SDK messages via the SDK's
custom-entry API, with the SDK's messages becoming one *input* (for LLM
context), not the source of transcript truth.

## Why it's worth it (value beyond the timestamp bug)

1. **Retires the divergence class** — not just timestamps. Any transcript event
   the SDK doesn't perfectly model (tool request vs result timing, app-origin
   user-confirmation, …) stops being ambiguously re-derived on restart.
2. **Durable-izes Outpost-Pi-specific events** — mesh tool cards, compaction
   markers, tool-request-as-distinct-from-result, steering — currently
   in-memory only, lost on restart.
3. **Decouples transcript time from SDK-persistence time** — events carry when
   they *actually happened* in the hook lifecycle, not when the SDK persisted
   for LLM context.
4. **Clean versioned extension point** — `outpost-pi.transcript-event.v1` makes
   future event kinds (approvals, annotations, …) additive + durable instead of
   crammed into SDK message semantics.
5. **Stable replay contract** — the app's `session_history` becomes exactly what
   was rendered live, durably; no re-derivation drift.
6. **Aligns with the repo's single-source-of-truth principle** — the transcript
   stops being an inferred projection (the smell) and becomes an owned durable
   aggregate. SDK owns LLM context; the extension owns the transcript.

## Cost / risk

Net-new durable responsibility for the extension (new module + codec +
backfill-preference + file-backed reopen tests), and a **second durable source**
(SDK messages + extension entries) that backfill must reconcile. The
reconciliation is the design-bearing core: SDK messages remain authoritative for
LLM context; extension entries are authoritative for the transcript.

## Spike (done — FEASIBLE)

`story-canonical-transcript-timestamp-ownership-ownership-foundation` carries
the read-only durability spike. Verdict: the SDK does **not** immutably own
`message.timestamp` (a `message_end` handler may return a same-role replacement;
`ExtensionAPI.appendEntry` → `SessionManager.appendCustomEntry` → session JSONL
→ recoverable via compaction-aware `buildContextEntries()`). Nuance: assistant
`message_end` fires **before** `tool_execution_start`, so the execution `ts`
can't be retrofitted into an already-persisted assistant message (esp.
multi-tool) — hence the custom-entry path rather than simple reuse. Full
live==durable agreement is achievable; no forced fallback residual.

## Decomposition sketch (for `epic-design` to refine)

- **F1 — Durable transcript event log (foundation).** Custom-entry codec
  (`outpost-pi.transcript-event.v1`), `appendEntry` binding, `TranscriptEventLog`
  becomes durable, backfill from `buildContextEntries()` preferring validated
  Outpost-Pi events over SDK-derived. The architectural capability.
- **F2 — Close the single-clock timestamp invariant.** Migrate the diverging
  kinds (tool_requested/finished, user_confirmed) to durable ownership; producer
  `ts` coverage (agent_done, error frames, user_message echoes, mesh cards);
  app consume cleanup. The timestamp payoff (the original motivation).
- **F3 — Durable-ize Outpost-Pi-specific events.** Mesh cards, compaction, and
  other extension-only transcript events become durable (currently in-memory).
- **F4 — Retire SDK-message re-derivation + two-source reconciliation.** Remove
  the lossy re-derivation; formalize SDK-messages-vs-extension-entries
  (LLM-context vs transcript) as the consistency contract.

## Relationship to in-flight work

`feature-canonical-transcript-timestamp-ownership` (implementing, 4 child
stories designed around the custom-entry plan from the spike) is the **seed** for
F1 + F2. `epic-design` will reconcile it — likely splitting its Unit A (durable
foundation) into F1 as a sibling feature, with the timestamp-payoff units (B/C/D)
becoming F2. The systematic enumeration
(`story-canonical-transcript-ordering-systematic-ts-provenance-sweep`) is the
ground-truth gap table for F2/F3.

`feature-canonical-transcript-ordering` (done) shipped the projection render-sort
that MOTIVATED this epic; it stays done. Its enumerated residual gaps are what
this epic retires.

## Next

`epic-design epic-durable-transcript-ownership` to decompose into features with
declared `depends_on` (F1 first; F2/F3 depend on it; F4 last), then feature-level
design + implement. The durable foundation (F1) is the riskiest, most novel unit
— design it first and most carefully.


## Decomposition (2026-08-25, epic-design reconciliation)

Pre-existing seed (`feature-canonical-transcript-timestamp-ownership`) split
per the sketch: its Unit A became F1; the seed IS F2. One child added (F3);
F4 closes the arc. Spike story absorbed by F1.

### Child features
- `epic-durable-transcript-ownership-durable-event-log` (F1) — durable event log foundation — depends on: []
- `feature-canonical-transcript-timestamp-ownership` (F2) — close the single-clock timestamp invariant — depends on: [F1]
- `epic-durable-transcript-ownership-durable-native-events` (F3) — durable-ize native events — depends on: [F1]
- `epic-durable-transcript-ownership-retire-rederivation` (F4) — retire re-derivation + two-source contract — depends on: [F1, F2, F3]

F2/F3 parallelize after F1. F1 is the riskiest unit (design it first and most
carefully, per the epic's own note).


## Drain record (2026-08-25)

All 4 features implemented in dependency order in one session:
- F1 durable-event-log (design 0b5092a0; impl aa6b52bb, ad030bc8, 40732a78) — codec/log/binding/reopen
- F2 timestamp-ownership (c144511b, d836116e, 5b87996f) — zero authoritative
  phone-clock paths remain
- F3 durable-native-events (design b320ab72; impl 5b94ddae, bc67b3f7, 28dd4a6f; completion 2468d43e) — tool/mesh/
  compaction/steering durable; sweep enumeration absorbed
- F4 retire-rederivation (design c060c9ec; impl 60da50b1; completion b68cbb34) — general path deleted; bounded
  mixed-era fallback retained; two-source contract at
  transcript_projection.ts:244
Extension suite 1079-1082 green throughout; app 944; protocol regenerated
(error.ts). Epic advances to review.


## Review record (2026-08-25)

**Thorough weight** — independent fresh-context pass, then a confirmation
pass, then a final surgical fix. Closed done.

- **Blockers (3 found → fixed → confirmed):** fork rehoming defeated by
  global event-id index (session-scoped identity, 0b998e74; + the
  confirmation pass caught the last-user recomputation leak it introduced,
  5e5c6687); era-blind FIFO claim matching (nearest-fact binding, 0b998e74);
  errors as third transcript authority (durable error events + history
  replay + shared app mapper, 7112464f).
- **Important (3):** stale _messageBuffer reference docs (7112464f);
  __proto__ clone hazard (0b998e74); non-atomic mesh pairs (0b998e74).
- **Nits (2):** drain-record inventory completed above; F2 evidence
  planned-vs-executed marked (7112464f).
- **Rejected (4):** delete-all-fallback, Rust/Cockpit regen, global append
  mutex, soak obsolescence — all upheld.
- Confirmation pass verified all five closures with file:line evidence
  and targeted suites (282-283 ext / 122 app / 7 codegen).
- Final state: 1088 extension tests, 946 app tests, protocol regenerated,
  946/1088 suites green. The divergence class the epic named (2026-08-03)
  is closed: zero authoritative phone-clock paths, session_history =
  exactly what rendered live (incl. errors), single transcript authority.
