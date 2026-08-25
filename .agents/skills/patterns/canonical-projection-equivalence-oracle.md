# Pattern: Canonical Projection Equivalence Oracle

## Rationale

An optimized reducer, a durable-era migration adapter, and a replay path can all look locally correct while drifting from the canonical transcript projection. Keep a simple reference implementation (or canonical serialized projection) as a test oracle. Feed both paths the same event prefixes, duplicates, and mixed-era inputs, then compare semantic output rather than incidental collection identity.

This makes performance work and persistence migrations safe: the faster path may change its internal data structures, but it cannot change the user-visible projection or replay contract.

## When to use

Use whenever a second implementation is introduced for a state projection:

1. Identify the simplest authoritative implementation or serialized output.
2. Run the candidate and oracle over the same input, including every event variant and relevant duplicate/reopen case.
3. Compare messages, turn state, event acceptance, and stable identities that are part of the contract.
4. Keep the oracle in tests; do not make production code call the slow path.

## When not to use

Do not compare arbitrary implementation details, object identity, map iteration order, or timestamps that are intentionally nondeterministic. If two projections have different documented purposes, write a contract test for each instead of asserting false equivalence.

## Examples

### Example 1: Incremental reducer is checked against full recomputation for every prefix

**File:** `app/test/domain/transcript/transcript_projection_test.dart:655-713`

```dart
for (final event in events) {
  prefix.add(event);
  final update = reducer.applyAll(<TranscriptEvent>[event]);
  _expectProjectionEquivalent(
    update.projection,
    deriveTranscriptProjection(sessionId: session, events: prefix),
  );
  expect(update.acceptedEvents, <TranscriptEvent>[event]);
}
```

The incremental implementation is continuously compared with `deriveTranscriptProjection`, including user, assistant, tool, failure, completion, and compaction variants.

### Example 2: Durable-entry reconciliation is checked against the durable canonical event list

**File:** `pi-extension/src/session/transcript_projection.test.ts:189-251`

```ts
const reopened = reconcileTranscriptContextEntries({ sessionId, entries });
expect(reopened).toEqual(durableEvents);
expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }))
  .toEqual(projectSessionHistory({ sessionId, events: durableEvents, limit: 10 }));
```

The test catches both authority mistakes (SDK text replacing durable text) and replay-shape drift after reopen.

### Example 3: Reopened error entries must project identically to the live event list

**File:** `pi-extension/src/session/transcript_projection.test.ts:117-160`

```ts
const live = projectSessionHistory({ sessionId, events: errors, limit: 10 });
const reopened = reconcileTranscriptContextEntries({
  sessionId,
  entries: errors.map((event) => durableEntry(event)),
});
expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 })).toEqual(live);
```

This uses the wire projection itself as the oracle for the durable reopen path, rather than asserting only that the custom entries decode.

### Example 4: Cross-surface replay fixtures assert the stable serialized contract

**File:** `pi-extension/src/extension.test.ts:6465-6535`

```ts
expect(fixture.assertions).toContain("duplicate replay appends zero events");
// Add the same local event and server replay twice, then request history.
expect(history.inner["events"]).toEqual([
  { ts: server.ts + 1, type: "user_input", id: local.clientMessageId, text: local.text },
  { ts: server.ts, type: "user_input", id: server.id, text: server.text },
]);
```

The fixture is a serialized oracle for reconnect semantics: duplicate history is replayed/idempotent, not treated as a replacement that loses the local prefix.

## Common violations

- Testing only the optimized path and assuming a successful build proves projection equivalence.
- Comparing only row counts, which misses stable-id, ordering, turn-state, and error-shape drift.
- Letting the oracle share the candidate's reducer or helper, so the test merely repeats the same bug.
- Omitting duplicate, replay, foreign-session, or mixed-era inputs from the oracle cases.

## Related

- `snapshot-replay-event-mappers.md` — canonicalizes snapshots before projection.
- `failure-first-regression-tests.md` — establishes the old failure boundary before checking the invariant.
- `cross-language-known-answer-fixture-triangulation.md` — the protocol-level form of an independently generated oracle.
