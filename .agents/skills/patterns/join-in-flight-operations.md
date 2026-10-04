# Join In-Flight Operations

Share one completion future for equivalent concurrent work, and release only
the matching operation on settlement.

## Rationale

Overlapping reconnect, recovery, and teardown requests often represent one
logical operation. Sharing its future preserves one completion boundary and
avoids cancellation cascades or duplicated destructive effects.

Equivalence must follow resource identity: joining a reconnect by peer
identity lets room selection change independently. Generation fencing remains
necessary for genuinely superseded operations; joining does not replace it.

## Examples

### 1. Same-peer connection requests share the ongoing handshake

**File**: `app/lib/data/transport/connection_manager.dart:765`

```dart
if (inFlight != null && _connectTarget?.peerEpk == target.peerEpk) {
  return inFlight;
}
```

The supervisor clears only its own operation after settlement:

```dart
_connectInFlight = operation;
void clearIfCurrent() {
  if (identical(_connectInFlight, operation)) {
    _connectInFlight = null;
    _connectTarget = null;
  }
}
```

Different peers still enter the replacement path; incidental room churn does
not cancel the shared handshake.

### 2. Concurrent transcript-discard requests share one destructive recovery

**File**: `app/lib/data/local/boxes.dart:168`

```dart
static Future<void> discardUnreadableTranscripts({
  TranscriptKeyValueStore? keyStore,
}) {
  final inFlight = _transcriptDiscardInFlight;
  if (inFlight != null) return inFlight;
  late final Future<void> tracked;
  tracked = _runTranscriptDiscard(keyStore ?? SecureTranscriptKeyValueStore())
      .whenComplete(() {
    if (identical(_transcriptDiscardInFlight, tracked)) {
      _transcriptDiscardInFlight = null;
    }
  });
  _transcriptDiscardInFlight = tracked;
  return tracked;
}
```

Every caller receives completion of the same discard rather than starting
overlapping wipes.

### 3. Lifecycle and command stops join the same extension teardown

**File**: `pi-extension/src/index.ts:1176`

```ts
function _goIdle(byeReason?: import("./protocol/types.js").ByeReason): Promise<void> {
  if (_goIdleInFlight) return _goIdleInFlight;
```

Both success and failure release the slot, without a stale completion
clearing a replacement. A further occurrence is device-ID provisioning at
`app/lib/data/identity/device_id.dart:38`, where concurrent callers share one
generation-and-persistence future.

## When to Use

- Equivalent requests may overlap while one operation owns a resource
  transition.
- Every caller must observe the actual shared completion.
- Duplicate work would cause competing writes, reconnect churn, or repeated
  teardown.

## When NOT to Use

- Requests target different owners, identities, or materially different
  inputs.
- Each request represents an independent command that must execute.
- The requirement is queuing, debounce, or permanent result caching rather
  than sharing current work.

## Common Violations

- Using a busy boolean and returning immediately instead of returning the
  shared future.
- Cancelling equivalent work because an unrelated presentation field changed.
- Joining requests whose security or ownership scope differs.
- Leaving a settled failure in a retryable in-flight slot.
- Clearing the slot unconditionally when an older operation can finish after
  replacement.
