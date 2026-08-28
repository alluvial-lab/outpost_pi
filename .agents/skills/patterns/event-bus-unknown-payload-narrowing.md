# Event-Bus Unknown-Payload Narrowing

## Rationale

Pi event buses and lifecycle hooks deliver untrusted or version-flexible payloads outside the generated wire decoder. Treat those payloads as `unknown` at the callback boundary, reject non-record values, and return a small typed projection only after checking the fields the consumer needs. Invalid or future-shaped events then become harmless no-ops instead of leaking casts into lifecycle state.

## When to use

Use at event-bus, SDK callback, and lifecycle-hook boundaries where payload shape is not guaranteed by the host:

1. Accept `unknown` in the callback or adapter.
2. Reject `null`, arrays, primitives, and missing fields immediately.
3. Check each consumed field's runtime type and semantic bounds.
4. Return a narrow value (`string | null`, a type guard, or a similarly small projection) and let the owner decide what to do.

## When not to use

Do not replace generated protocol decoding for wire frames with ad-hoc event checks. Do not repeatedly narrow a value that has already crossed a typed domain boundary, and do not retain arbitrary payload objects after extracting the fields needed by the owner.

## Examples

### Example 1: Background lifecycle events extract only a valid identifier

**File**: `pi-extension/src/extension/background_activity.ts:17-21`

```ts
function backgroundId(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return null;
  const id = (payload as BackgroundPayload).id;
  return typeof id === "string" ? id : null;
}
```

The tracker ignores malformed `created` and terminal events rather than allowing an invalid id into its active set.

### Example 2: Child-session callbacks narrow the only field used by ownership state

**File**: `pi-extension/src/extension/runtime_coordinator.ts:149-153`

```ts
function childSessionId(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const sessionId = (payload as { sessionId?: unknown }).sessionId;
  return typeof sessionId === "string" && sessionId.length > 0 ? sessionId : null;
}
```

The coordinator records child lifecycle state only for non-empty string identifiers.

### Example 3: Session lifecycle hooks validate optional event metadata

**File**: `pi-extension/src/extension/composition_root.ts:197-200`

```ts
function isSessionEvent(event: unknown): event is { reason?: string } {
  return typeof event === "object" && event !== null && "reason" in event
    && typeof (event as { reason?: unknown }).reason === "string";
}
```

`sessionReason` can safely map an unknown SDK event to the closed lifecycle-reason set while preserving its fallback for malformed or absent metadata.

## Common violations

- Casting an event payload directly to a domain object and reading fields without a runtime check.
- Treating arrays or `null` as records because JavaScript permits property access on some non-record values.
- Keeping the whole unknown payload in state when only one validated identifier or reason is needed.
- Making the event callback responsible for protocol decoding that belongs to a generated wire boundary.

## Related

- `typed-wire-decoders.md` — validates protocol text and generated wire objects at transport boundaries.
- `content-free-diagnostic-categories.md` — projects malformed boundary failures into safe, bounded diagnostics.
