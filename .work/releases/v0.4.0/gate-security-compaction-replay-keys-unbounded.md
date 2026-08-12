---
id: gate-security-compaction-replay-keys-unbounded
kind: story
stage: done
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: security
created: 2026-07-20
updated: 2026-08-11
---

# Compaction replay-suppression keys grow for the full owner-channel lifetime

## Severity
Low

## Domain
API Security / Resource Exhaustion

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/owner_multiplexer.ts:566`

## Evidence
```ts
let keys = this.flushedCompactionKeysByPeer.get(peerId);
if (!keys) {
  keys = new Set<string>();
  this.flushedCompactionKeysByPeer.set(peerId, keys);
}
keys.add(`${message.session_id ?? ""}:${message.ts}`);
```

Every successful offline-buffer compaction flush adds a key. `arbitrateSessionHistory()` only reads the set; it never retires entries, and the set is cleared only when the owner channel detaches (`owner_multiplexer.ts:425`). A paired owner can request compaction (`pi-extension/src/index.ts:2611`) and reconnect repeatedly, while old-session keys remain retained even after they can no longer match current history. Sustained compaction/reconnect cycles therefore grow process memory for the lifetime of a long-lived owner channel. Each entry is small and exploitation requires repeated completed compactions plus presence flaps, so this is defense-in-depth rather than a release blocker.

## Remediation direction
Bound replay-suppression state to the current session and prune obsolete session keys on session rotation. Prefer convergent live/replay compaction identity that removes the side registry; if the registry remains, add an explicit per-peer ceiling or expiry that preserves the intended repeated-sync and multi-device behavior.

## Implementation notes

- Capped each connected owner's flushed-compaction replay registry at 128 newest
  identities, evicting the oldest identity first.
- Added a regression that flushes 129 compactions and proves only the evicted
  oldest compaction returns in a subsequent history replay.
- Changed `pi-extension/src/extension/owner_multiplexer.ts` and its test.
- Verified with `vitest run src/extension/owner_multiplexer.test.ts` (29 tests)
  and `tsc --noEmit`.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
