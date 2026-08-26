# Pattern: Dual-Execution-Path Contract Documentation

## Rationale

A typed operation can have one wire action but different execution semantics
when capability availability or process ownership changes. Document both paths
at every normative surface: the in-process capability path, the managed
restart/fallback path, who owns acknowledgement and teardown, and which
successor state is authoritative. This prevents a README or protocol table from
promising an SDK call that is unavailable in daemon mode, or from presenting a
process exit as proof that work was delivered.

## When to use

Use when one public action crosses an execution boundary such as interactive
versus daemon, in-process versus restart-managed, or local versus externally
owned lifecycle:

1. Keep one canonical action/discriminator in the protocol table.
2. State the capability-dependent path and the fallback path next to that
   action, including guards, ownership, and failure behavior.
3. Repeat the contract in the user-facing surface and the agent/developer
   reference, using the same operation names and sentinel values.
4. Name the post-transition convergence signal and distinguish it from the
   dispatch acknowledgement.

## When not to use

Do not document only the happy path when the fallback is shipped, and do not
invent a second wire action merely to describe an implementation difference.
Do not call a bounded shutdown deadline delivery proof; use the durable recovery
boundary when completion can be lost at a hard process boundary.

## Examples

### Protocol surface names both session-new paths and convergence

**File:** `PROTOCOL.md:256-270`

```markdown
| New session | `session_new` | `ctx.newSession()` in-process; managed restart-fresh lifecycle described below |

`session_new` has two execution paths. In an in-process command context,
`ctx.newSession()` replaces the SDK session ... In daemon/restart-wrapper mode ...
the extension installs a synchronous restart fence ... and exits with
`EXIT_FRESH_SESSION` (`42`) ... without `--continue`.
```

The canonical protocol identifies the same wire action, capability boundary,
fence/drain/teardown order, sentinel, and liveness-versus-delivery distinction.

### User documentation preserves the fallback behavior

**File:** `pi-extension/README.md:133-142`

```markdown
| **New session** | Runs `ctx.newSession()` in an interactive command context ...
In daemon/restart-managed mode, it acknowledges and exits with
`EXIT_FRESH_SESSION` (`42`) so the supervisor or wrapper relaunches Pi without
`--continue`. |
```

The user-facing action table does not imply that an interactive command context
exists in a managed process.

### Agent reference repeats the lifecycle guard

**File:** `.agents/skills/pi-extension-typescript/SKILL.md:166-175`

```markdown
- in daemon/RPC or restart-wrapper mode, `session_new` can acknowledge, reset
the mirror, and exit with `EXIT_FRESH_SESSION` (`42`) so the supervisor or
wrapper respawns a fresh Pi session without `--continue`; do not accidentally
turn this into an in-process session switch without preserving the restart
contract;
```

The stack reference gives implementers the same operation, sentinel, and
relaunch rule while directing them not to reuse a stale in-process capability.

## Common violations

- Showing `ctx.newSession()` as universally available when it is command-context
  only.
- Omitting who drains or retries work in the managed path.
- Treating `action_ok` as proof of the visible successor session rather than
  documenting the authoritative successor room/session metadata.
- Updating the protocol table but leaving README or stack guidance with a stale
  sentinel, path, or convergence claim.

## Related

- `generation-fenced-async-ownership.md` — guards async continuations across the
  replacement these documents describe.
- `durable-first-visibility-gating.md` — separates durable confirmation from
  live visibility after the path converges.

## Index entry

- **dual-execution-path-contract-documentation**: Document capability-dependent operations as both in-process and managed-restart paths, including ownership, acknowledgement, teardown, and convergence.
