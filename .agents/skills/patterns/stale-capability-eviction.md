# Pattern: Stale Capability Eviction

## Rationale

Pi invalidates SDK contexts after session replacement or reload; even reading a guarded property can then throw. A callback that keeps a captured context or API must recognize that specific stale-context failure, evict only the captured value that failed, and then use the operation's normal failure semantics. Identity-checked eviction is essential: a late rejection from an old API must never clear a newer session's capability.

This keeps stale callbacks from crashing the extension or repeatedly retrying a capability that Pi has revoked, while preserving real delivery and action errors for their callers.

## When to use

Use this when an extension callback retains a replaceable Pi SDK context, message API, or action API across an async boundary.

1. Capture the capability before invoking it.
2. Detect Pi's stale-context error at the invocation boundary, including a returned promise's rejection when the API may be async.
3. Clear the stored reference only when it is still the captured value.
4. Return the operation's documented degraded result or rethrow non-stale and action failures as appropriate.

## When not to use

Do not turn every SDK error into a stale-capability result. Provider, validation, and user-action failures remain meaningful errors. Do not clear a global current capability unconditionally: a newer `session_start` or `withSession` binding may already have replaced it.

## Examples

### Message rendering handles synchronous and asynchronous stale failures

**File:** `pi-extension/src/session/sdk_session_projection.ts:760-775`

```ts
const api = this.messageApi;
if (!api) return false;
try {
  const delivered = api.sendMessage(...args);
  if (isPromiseLike(delivered)) {
    delivered.catch((err: unknown) => {
      if (isStaleContextError(err)) this.forget(api);
    });
  }
  return true;
} catch (err) {
  if (isStaleContextError(err)) this.forget(api);
  return false;
}
```

`forget` checks that `api` is still `messageApi` before clearing it, so an old rejection cannot evict a re-armed API.

### Agent wake classifies stale delivery as recoverable

**File:** `pi-extension/src/session/sdk_session_projection.ts:777-795`

```ts
try {
  await api.sendUserMessage(...args);
  return { ok: true };
} catch (err) {
  const stale = isStaleContextError(err);
  if (stale) this.forget(api);
  return { ok: false, detail: err instanceof Error ? err.message : String(err), recoverable: stale };
}
```

The caller can queue a recoverable handoff until a fresh session binding arrives, but still surfaces a real delivery failure.

### Wrapped action APIs evict the stale action capability before rethrowing

**File:** `pi-extension/src/session/sdk_session_projection.ts:1057-1083`

```ts
private forgetActionApi(api: FreshActionApi): void {
  if (api === this.actionApi) this.actionApi = null;
  if (api === this.messageApi) {
    this.messageApi = null;
    this.opts.outputs.onStaleMessageApi?.(api as AgentMessageApi);
  }
}

setModel: async (model: SdkModelLike) => {
  if (typeof api.setModel !== "function") throw new Error("Pi model API unavailable for the current session");
  try {
    return await api.setModel(model);
  } catch (err) {
    if (isStaleContextError(err)) this.forgetActionApi(api);
    throw err;
  }
},
```

The same wrapper applies the rule to `setThinkingLevel`, preserving the action caller's error contract.

### Guarded context access removes only stale candidate slots

**File:** `pi-extension/src/index.ts:530`

```ts
try {
  return ctx.ui;
} catch (err) {
  if (_isStaleContextError(err)) {
    if (ctx === _lastCtx) _lastCtx = null;
    if (ctx === _lastEventCtx) _lastEventCtx = null;
  }
  return undefined;
}
```

A relay callback falls back to a fresher context or no-op rather than using the invalid one again.

## Common violations

- Clearing the current SDK API after any error, which discards a valid replacement capability.
- Handling only synchronous throws and leaving a promise rejection to retain a stale API.
- Treating real provider or validation failures as recoverable session replacement.
- Continuing to dereference a context after its stale error instead of returning or retrying through a fresh binding.

## Index entry

- **stale-capability-eviction**: On a Pi stale-context error, evict only the matching captured capability before degrading or propagating the failure.
