# Pattern: Durable Transition Latches

## Rationale

A destructive multi-step transition (wipe pairings, disconnect, erase
transcripts, then activate replacement state) can be interrupted by a crash
or kill between steps. Ordering the steps with `await` is not enough: the
interrupted device must converge on boot, not resume with half-removed
capabilities. The transition writes a durable pending record (the latch)
BEFORE removing old capabilities, gates readers while latched, detects and
finishes the latched transition at boot, and deletes the latch only after
every destructive and recovery step succeeds.

## When to use

Use this pattern for crash-interruptible destructive state transitions whose
partial completion would violate an isolation boundary: owner-identity
replacement, account transitions, destructive storage migrations.

1. Persist the latch before the first destructive step, outside any prefix
   the cleanup itself wipes.
2. Gate every accessor of the protected state while the latch exists
   (fail closed: return null / throw, never best-effort).
3. At boot, detect the latch and resume/finish cleanup before activating
   any replacement state.
4. Commit the replacement and delete the latch only after all steps succeed;
   on failure, keep the latch so the next boot retries.

## When not to use

Do not use for reversible or in-memory operations, or where a generation
fence alone (`generation-fenced-async-ownership`) already prevents stale
side effects. The latch exists for durable cross-restart convergence, not
in-process ordering.

## Examples

### Owner transition marker gates identity access until cleanup commits

**File:** `app/lib/pairing/storage.dart:343-371`

```dart
// This marker is deliberately outside the prefixes cleared by [wipeAll]. It
// makes an interrupted Owner transition retryable before any identity gains
// access to the previous Owner's local state.
const _kOwnerTransitionService = 'dev.outpostpi.owner-transition';
```

### Bridge fail-closed getters while latched

**File:** `app/lib/pairing/owner_identity_bridge.dart:64-72`

```dart
OwnerIdentity? get currentIdentity => _transitionPending ? null : _current;
Uint8List? get currentOwnerPk =>
    _transitionPending ? null : _current?.ownerPk;
```

### Boot resumes the latched cleanup before activation

**File:** `app/lib/routing/app_router.dart:119-143` — `OwnerTransitionPending`
boot result runs `cleanPendingOwnerTransition`, then
`completePendingTransition` commits the identity and deletes the marker.

## Common violations

- Writing the latch after the destructive steps begin (a crash between them
  is invisible to the next boot).
- Deleting the latch before the final commit (a failed delete-then-crash
  leaves ungated partial state).
- Gating only the primary accessor while a secondary reader (e.g. a cached
  public key getter) still exposes pre-transition state.
