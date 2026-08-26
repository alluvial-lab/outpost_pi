---
id: feature-mobile-slash-command-invocation
kind: feature
stage: review
tags: [app, pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-26
---

# Mobile command invocation (dedicated-operations model)

## Brief

Let the mobile app invoke only the Pi operations it actually needs through a
curated, typed operation per command. The core result is that the existing
mobile **New session** action works even when an interactive extension has never
received an `ExtensionCommandContext`: the extension accepts `session_new`,
rotates its session projection, and asks its owning process manager for one
fresh restart. A separate verify-first research child may identify extension-
owned commands that deserve their own dedicated mobile operations.

This feature does **not** add a generic slash-command invocation API, route
slash-prefixed composer text differently, or revive the rejected editor seam.

## Status reconciliation

The feature returned to `drafting` after the editor-seam design was rejected,
but its two restart-fresh checkpoints were subsequently implemented and shipped
in `v0.4.0` while the parent remained stale:

- `.work/releases/v0.4.0/story-new-session-restart-fresh-extension-exit.md`
- `.work/releases/v0.4.0/story-new-session-restart-fresh-restart-mechanism.md`

The Herdr fleet adoption that the second checkpoint left as an operational
follow-up later landed in commit `310b20d8`: cold starts use the restart wrapper
for every project pane and `scripts/wrap-agents.sh` converts already-running
idle bare agents. The remaining active child,
`story-mobile-extension-command-invocation`, was an independent research input
and is now done. This parent records the realized core design; research
consumption and current-state verification are the remaining implementation
close-out work before feature review, and no already-delivered checkpoint is
recreated.

## Rejected direction (do not revisit)

A prior spike proved that `setEditorComponent` plus a retained `onSubmit`
callback can reach Pi's TUI parser. A `gpt-5.6-sol` design review rejected that
as a product boundary:

- replacing the editor cannot transparently preserve the default editor's full
  state and conflicts with other editor extensions;
- programmatic `onSubmit` can clobber a draft being composed in the TUI;
- the callback is a user-event implementation detail with no correlated result;
- unknown slash-prefixed composer input can fall through as a model prompt;
- RPC/daemon mode has no equivalent seam.

The installed SDK exposes no general command-invocation API. Session-control
methods such as `newSession` are deliberately command-context-only, while safe
base-context operations such as `compact` already have dedicated mobile
actions. The design follows that capability boundary rather than bypassing it.

## Design decisions

- **Mobile command model**: retain one typed operation per supported need — this
  matches `PROTOCOL.md`, the generated action vocabulary, and Pi ecosystem
  adapters; arbitrary command strings remain out of scope.
- **No-context `/new`**: use the process-manager handshake when
  `ExtensionCommandContext.newSession` is absent — a managed restart is the
  smallest supported way to create a genuinely fresh interactive Pi session.
- **Safety gate**: exit only when `OUTPOST_PI_DAEMON=1` or
  `OUTPOST_PI_UNDER_RESTART_WRAPPER=1`; an unmanaged process returns
  `fresh_session_restart_unavailable` without resetting or exiting.
- **Interactive manager**: run every Herdr project pane under the existing,
  cwd-parameterized `scripts/pi-restart-loop.sh` — it owns both the child exit
  and the successor launch, unlike Herdr itself. A persisted “fresh next time”
  marker was rejected because it cannot relaunch a pane and adds durable state
  without solving process ownership.
- **Acknowledgement semantics**: `action_ok` means the managed process accepted
  the destructive operation. Completion is established by the successor's
  canonical room metadata carrying a new `session_id`; reconnect hydration, not
  the pre-exit process, is the convergence boundary.
- **Existing UI**: reuse the current New-session quick action and confirmation;
  the core feature adds no screen, component, or visual behavior, so no fallback
  mockup is warranted.
- **Research consumption**: do not pre-create speculative implementation work.
  When `story-mobile-extension-command-invocation` finishes, consume its
  per-command table. A command is eligible only if it is useful on mobile and
  callable from a fresh base context. Each eligible capability gets a named,
  typed dedicated operation in a follow-up child depending on the research
  story; no result may become `extension_command {command,args}` or another
  general dispatcher. If no command qualifies, record the no-change result and
  finish the feature.
- **Execution mapping**: direct-read mapping was used because this delegated
  worker has no generic exploratory-subagent adapter. The code paths were
  bounded and verified against the shipped child items, current source, tests,
  wrapper scripts, and operator runbook.
- **Review policy**: effective `review_weight` is `standard` (caller/default),
  so the completed feature receives one balanced fresh-context pass after
  implementation verification; reviewer findings remain proposals.

## Architectural choice

### Option A — upstream host-operation gateway

A public Pi API such as `requestHostOperation({type: "new_session"})` would let
the host serialize replacement safely and work across modes. It is the clean
long-term general solution, but the installed SDK does not expose it and an
upstream delivery cannot block the reported bug.

### Option B — dedicated operation plus restart-fresh handshake (chosen)

Keep the generated `session_new` wire action. Use command-context
`newSession({withSession})` when Pi has supplied that capability; otherwise,
only under an owning supervisor/wrapper, acknowledge, clear the outgoing
session projection, and exit with the shared fresh-session code. The owner
relaunches once without `--continue`. This preserves the curated protocol,
works with the SDK's capability model, and fails closed in unmanaged modes.
Its tradeoff is an explicit operational requirement: interactive Pi must run
under the wrapper.

### Option C — general TUI/editor submission bridge (rejected)

This appears broad but depends on private TUI wiring, is not mode-independent,
can destroy user draft state, and cannot provide a reliable correlated result.
The apparent generality is not worth the correctness and lifecycle hazards.

## Implementation Units

### Unit 1: Accept `session_new` through current or manager-owned capabilities

**Files**:
- `pi-extension/src/actions/handlers.ts`
- `pi-extension/src/index.ts`
- `pi-extension/src/extension.test.ts`

**Story**: `story-new-session-restart-fresh-extension-exit` (done, released in
`v0.4.0`)

```ts
export interface ActionCtx {
  newSession?: (options?: {
    withSession?: (ctx: ActionCtx) => Promise<void>;
  }) => Promise<{ cancelled: boolean }>;
}

export async function handleSessionNew(
  ctx: ActionCtx & { newSession: NonNullable<ActionCtx["newSession"]> },
  sender: ActionReplySender,
  msg: Extract<ClientMessage, { type: "session_new" }>,
  onReplaced?: (freshCtx: ActionCtx) => void,
): Promise<boolean>;

export function _routeClientMessageFrom(
  sender: PlainPeerChannel,
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void;
```

**Implementation notes**:
- Ask `SdkSessionProjection.freshCommandActionCtx()` first. If it exposes
  `newSession`, keep the in-process `withSession` path and bind only the fresh
  replacement context.
- If no command capability exists, require a manager ownership env. Send
  sender-scoped `action_ok`, call `_resetSessionForNew(msg.id)`, then schedule
  `process.exit(EXIT_FRESH_SESSION)` after the bounded acknowledgement window.
- If ownership is absent, send `action_error`; do not clear transcript state,
  rotate session identity, or exit.
- `_resetSessionForNew` converges the turn to idle, clears queued/in-flight and
  capture-upload state, rotates the remote session identity, and broadcasts the
  compatibility empty history before process replacement.
- The wire remains the schema-generated `session_new`/`action_ok`/
  `action_error` contract. No app or schema change belongs in this unit.

**Acceptance criteria**:
- [x] A wrapper-managed, no-command-context `session_new` sends `action_ok`,
      resets the outgoing session projection, and exits with the shared fresh
      code in that order.
- [x] An unmanaged no-command-context request sends a structured error and
      neither resets nor exits.
- [x] A command-capable request still uses `newSession({withSession})` and does
      not retain the stale predecessor context.
- [x] Daemon behavior remains on the same restart-fresh contract.

---

### Unit 2: Relaunch exactly once without `--continue`

**Files**:
- `pi-extension/src/daemon/rpc_child.ts`
- `pi-extension/src/daemon/supervisor.ts`
- `pi-extension/src/daemon/rpc_child.test.ts`
- `pi-extension/src/daemon/supervisor.test.ts`
- `scripts/pi-restart-loop.sh`
- `pi-extension/src/pi_restart_loop.test.ts`

**Story**: `story-new-session-restart-fresh-restart-mechanism` (done, released
in `v0.4.0`; depends on
`story-new-session-restart-fresh-extension-exit`)

```ts
/** Process-manager handshake requesting one restart without `--continue`. */
export const EXIT_FRESH_SESSION = 42;

export function rpcSpawnArgs(
  extensionPath: string,
  sessionName?: string,
  useContinue?: boolean,
): string[];
```

```text
scripts/pi-restart-loop.sh [cwd] [pi-arg ...]
  exports OUTPOST_PI_UNDER_RESTART_WRAPPER=1
  normal launch       -> pi --continue <args>
  child exit 42       -> pi <args> exactly once
  later hot reload    -> pi --continue <args>
```

**Implementation notes**:
- `RpcChild` consumes `EXIT_FRESH_SESSION` by setting a one-shot
  `forceFreshSessionOnNextSpawn`; it clears the flag before spawning so a later
  crash cannot accidentally create another fresh session.
- `Supervisor` treats exit 42 as intentional immediate recycle and does not
  consume crash-backoff budget.
- The interactive wrapper recognizes only exit 42 as the fresh restart signal.
  Exit 0 still requires the exact validated PID marker for hot reload, and all
  other nonzero exits retain crash-stop behavior.
- The TypeScript constant is authoritative for extension/daemon code. The shell
  copy is pinned by comment and by a process harness importing the TypeScript
  value; introducing a generated shell contract would cost more than this
  single stable handshake earns.

**Acceptance criteria**:
- [x] Daemon and interactive paths use the same exit code and omit
      `--continue` for exactly the successor spawn.
- [x] The fresh one-shot resets before launch; a later authorized hot reload
      resumes the fresh session with `--continue`.
- [x] Normal quit and non-fresh crashes do not become restart loops.
- [x] Wrapper ownership is visible to the extension only in children actually
      launched by that wrapper.

---

### Unit 3: Put every interactive Herdr Pi under the owning wrapper

**Files**:
- `scripts/herdr-start-agents.sh`
- `scripts/wrap-agents.sh`
- `scripts/refresh-dist.sh`
- `AGENTS.local.md`

**Checkpoint**: operational completion of
`story-new-session-restart-fresh-restart-mechanism` (landed after its release in
commit `310b20d8`; no retroactive child story)

```text
scripts/herdr-start-agents.sh  # cold-start every project pane under wrapper
scripts/wrap-agents.sh         # convert idle bare Pi children; skip working/wrapped
scripts/refresh-dist.sh        # restart wrapped agents with --continue
```

**Implementation notes**:
- Discover panes dynamically; agent count and workspace labels are not part of
  the capability contract.
- `herdr-start-agents.sh` sends the cwd-parameterized wrapper command instead of
  `herdr agent start -- --continue`, because Herdr persists panes but does not
  supervise child exits.
- `wrap-agents.sh` is the recovery/adoption path for restored bare processes. It
  skips active turns, waits for the old Pi to leave the foreground, launches
  the wrapper, and verifies both wrapper and child are present.
- `refresh-dist.sh` remains the separate resume-preserving operation. Fresh
  session and hot reload share process ownership but not restart signals.

**Acceptance criteria**:
- [x] Cold-started project panes launch under `pi-restart-loop.sh` regardless of
      which repository owns their cwd.
- [x] Existing idle bare agents can be converted without changing sessions;
      working and already-wrapped agents are not interrupted.
- [x] The operator runbook explains post-reboot bare-process recovery and how to
      verify wrapper parentage.
- [ ] Operator phone-attached UAT (not rerun by this headless close-out): New
      causes a brief disconnect, the same room returns with a new canonical
      `session_id`, and the transcript hydrates empty. Current-tree automated
      coverage must prove the same contract before the feature enters review.

---

### Unit 4: Consume extension-command research without widening the command surface

**File**: `.work/active/stories/story-mobile-extension-command-invocation.md`

**Story**: `story-mobile-extension-command-invocation` (research, done;
`depends_on: []`)

```ts
type ExtensionCommandFinding = {
  command: string;
  requiredContext: "base" | "command";
  mobileInvocable: boolean;
  mobileNeed: string | null;
};
```

**Implementation notes**:
- Treat the research table as evidence, not pre-authorization to add a wire
  dispatcher.
- For each base-context-safe result, first confirm a concrete mobile need.
  Create a follow-up child only when both conditions hold, with
  `depends_on: [story-mobile-extension-command-invocation]` and a named typed
  request/reply contract for that operation.
- If all commands are command-gated, local-UI-only, configuration-only, or have
  no mobile need, record that outcome here and make no code/UI change.
- Do not block core restart-fresh implementation on this independent research.

**Acceptance criteria**:
- [x] The research child records a verified per-command capability table.
- [x] Every proposed implementation result is rejected below with a concrete
      mobile-need or runtime rationale; no follow-up child is warranted.
- [x] No generic slash-command, command-name, or arbitrary-args action enters
      the generated protocol.

## Implementation order

1. `story-new-session-restart-fresh-extension-exit` — accept/reset/exit contract
   (done).
2. `story-new-session-restart-fresh-restart-mechanism` — daemon/wrapper one-shot
   fresh successor (done; depends on step 1).
3. Herdr wrapper fleet adoption — realized operational completion of step 2
   (done; no retroactive child).
4. `story-mobile-extension-command-invocation` — independent research done.
5. Consume step 4 — done with the no-change adjudication below; no command met
   both the base-context and concrete-mobile-need gates.
6. Run current-state verification and advance to the feature's one standard
   fresh-context review. The phone-attached lifecycle smoke remains an operator
   UAT checkpoint; this headless close-out uses the caller-required owning
   suites and does not claim that smoke was rerun here.

## Child-story graph

- `story-new-session-restart-fresh-extension-exit` — `depends_on: []` — done,
  released in `v0.4.0`.
- `story-new-session-restart-fresh-restart-mechanism` —
  `depends_on: [story-new-session-restart-fresh-extension-exit]` — done,
  released in `v0.4.0`.
- `story-mobile-extension-command-invocation` — `depends_on: []` — research
  done.
- Conditional follow-up — not created: no command passed both eligibility
  gates.

No new story is spawned: the core checkpoints already exist and are complete,
and the completed research did not establish a concrete mobile need that would
justify a new dedicated wire operation.

## Research-consumption adjudication (2026-08-26)

**Decision: no protocol or app change.** The research proves that many
extension-owned handlers can be refactored to run from base context, but that is
only the runtime half of the gate. The current mobile product contract names
prompting, compaction, model/thinking control, and session replacement as its
curated controls; the app already implements those as typed actions. The
remaining command surface is local setup, host/fleet administration, duplicated
snapshot information, or a security-sensitive operation without an approved
mobile journey. Adding any of it now would manufacture product scope from SDK
reachability rather than consume a demonstrated mobile need.

Per-command result:

- `/outpost-pi` — decline: configured sessions already auto-connect and publish
  canonical reachability; first-run behavior enters a local interactive setup
  flow, so there is no distinct mobile operation.
- `/outpost-pi setup` — decline: requires `ui.select` and edits cwd-local host
  configuration; it is not callable from a fresh notification-only base
  context.
- `/outpost-pi hot-reload` — decline: local development/process-management
  operation, explicitly unavailable in daemon mode and not a mobile product
  control.
- `/outpost-pi status` — decline: base-context-safe, but the app already receives
  authoritative connection, room, model, thinking, and working snapshots;
  formatted `ui.notify` status would be a second, weaker authority.
- `/outpost-pi stop` — decline: base-context-safe but tears down the same mesh
  and relay path carrying the request; no mobile recovery journey requires it.
- `/outpost-pi pair` — decline: current daemon/non-TUI execution is rejected
  without the private pair-code-file seam, and pairing remains the purpose-built
  local QR flow rather than an already-paired remote action.
- `/outpost-pi devices` — decline: base-context-safe, but it lists Owner devices
  known to one extension; the app's Settings already owns its paired-PC roster
  and no mobile owner-device administration journey is specified.
- `/outpost-pi revoke` — decline: reverse-side owner revocation is
  security-sensitive and would conflict with the settled app-owned revoke plus
  implicit cross-side signaling contract.
- `/outpost-pi set-relay` — decline: mutates host bootstrap configuration and can
  cut off the active channel; relay setup remains a local operator action.
- `/outpost-pi peers` — decline: returns coding-agent mesh addresses, not human
  app sessions; Home already consumes the room/session inventory needed on
  mobile.
- `/outpost-pi create` — decline: filesystem and supervisor administration with
  host-local cwd trust belongs to CLI/Cockpit, not the session quick-action
  surface.
- `/outpost-pi remove` — decline: destructive host registry/process mutation has
  no approved mobile fleet-management journey.
- `/outpost-pi daemons` — decline: base-context-safe, but a full host fleet
  inventory is outside the current session-control mobile contract.
- `/outpost-pi daemon start` — decline: host fleet mutation is CLI/Cockpit scope;
  no concrete mobile need is recorded.
- `/outpost-pi daemon stop` — decline: destructive host fleet mutation lacks a
  mobile authorization/recovery design.
- `/outpost-pi daemon restart` — decline: disruptive fleet mutation is distinct
  from the existing typed `session_new` action for the active session and must
  not be smuggled in as another restart control.
- `/outpost-pi daemon status` — decline: fleet-wide operational status has no
  current mobile journey; active-room reachability already hydrates through the
  canonical snapshot contract.
- `/outpost-pi daemon send` — decline: arbitrary supervisor prompt injection
  would bypass the app's session-scoped `user_message`, durable outbox, and
  acknowledgement semantics.
- `/outpost-pi cron` — decline: scheduler CRUD/run/log is a multiplexed host
  administration surface with prompt-bearing and destructive subcommands; it
  needs a separately approved product design, not one command-shaped action.
- `/outpost-pi install` — decline: privileged host-service installation needs
  local OS/admin interaction and is explicitly unsuitable for mobile remote
  invocation.
- `/outpost-pi uninstall` — decline: privileged, destructive host-service
  removal remains local and has no mobile recovery path.

The generated schema, extension router, and app contain no `extension_command`,
command-name, or arbitrary-args dispatcher. Late binding therefore terminates
this conditional branch without children.

## Simplification

- Retain the existing schema-generated `session_new` action and current app
  repository/quick-action path; adding a second command transport would create
  competing authorities for the same operation.
- Use the same `EXIT_FRESH_SESSION` handshake for daemon and wrapper ownership;
  do not retain daemon-only naming or a separate marker protocol.
- Run Herdr children under the existing wrapper instead of building a second
  Herdr-specific supervisor.
- Do not add a command picker, composer parsing, editor replacement, protocol
  version, or compatibility shim.
- No tests are removed: the existing action, extension, daemon, wrapper, and app
  repository tests cover distinct stable seams.

## Testing

- **Extension interface/regression** —
  `pi-extension/src/extension.test.ts` protects ACK/reset/exit ordering,
  unmanaged fail-closed behavior, daemon regression, successor session
  rotation, and stale-context avoidance.
- **Process-manager contract** — `pi-extension/src/daemon/rpc_child.test.ts`,
  `pi-extension/src/daemon/supervisor.test.ts`, and
  `pi-extension/src/pi_restart_loop.test.ts` protect the shared exit code,
  one-shot omission of `--continue`, immediate daemon recycle, normal quit, and
  hot-reload resume behavior.
- **Existing app boundary** —
  `app/test/data/actions/actions_repository_test.dart` and
  `app/test/ui/chat/quick_actions/quick_actions_sheet_test.dart` protect the
  typed request/reply correlation, destructive confirmation, reset-after-ACK,
  and visible failure behavior. Re-run them only if research produces app work;
  no app code changes are required for the core.
- **Owning suites** — from `pi-extension/`, run repo-local-cache-prefixed
  `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build`.
  Run `bash -n` on the touched wrapper/fleet scripts. If a research follow-up
  changes app code, also run `flutter analyze` and
  `flutter test --exclude-tags e2e` from `app/` with the documented toolchain.
- **Manual lifecycle smoke** — from the existing mobile New action, verify a
  wrapped interactive agent that initially resumed with `--continue` exits,
  reconnects in the same room with a different canonical `session_id`, hydrates
  an empty transcript, and can later hot-reload/resume that new session.

## Risks

- **Pre-exit ACK delivery is best-effort.** The extension accepts and sends
  `action_ok` before exiting, but there is no relay delivery ACK. The canonical
  successor room snapshot is the correctness path; the app may transiently
  report an action failure if the ACK is lost even though session rotation
  succeeds. Durable action-result recovery is broader reliable-delivery work,
  not a reason to add an unsafe command seam here.
- **Wrapper ownership is operational.** After a host reboot, Herdr may restore a
  bare Pi process without its wrapper parent. The extension then fails closed
  rather than killing the pane. `scripts/wrap-agents.sh` is the documented
  recovery; the live smoke must verify the actual parent before claiming the
  capability.
- **A fresh restart is destructive.** The operation can end an active turn and
  intentionally abandons the old session. The existing confirmation is the
  user authorization; this path must not be reused for non-destructive actions.
- **Process exit is not session lifecycle completion.** The outgoing process can
  clear its projection, but only successor `session_start` plus room metadata
  proves a fresh Pi session exists. Tests and UI must not treat the 100 ms timer
  as completion evidence.
- **Research may produce no implementation.** Extension-owned commands can still
  require command-only context or local TUI interaction. A verified no-change
  result is valid and must not be converted into a general command action to
  manufacture scope.

## Implementation close-out (2026-08-26)

### Execution and dependency reconciliation

- Scope resolved to this feature and its completed checkpoints. The two
  restart-fresh children are terminal in `v0.4.0`; the research child is
  terminal in the active tier; the graph is acyclic and has no unmet external
  dependency.
- Execution stayed inline because this delegated host exposes no subagent tool.
  Worker capability was the caller-selected `openai-codex/gpt-5.6-sol` at
  `xhigh`; one cohesive owner was appropriate because the only remaining work
  was research consumption plus verification, not a code wave.
- Research consumption produced the no-change adjudication above. No child was
  created, no schema/code/app file changed, and no generic command dispatcher
  was introduced.

### Current-state contract verification

Direct source inspection on the current tree confirmed:

- `protocol/schema/app-pi-client.schema.json` still enumerates the curated
  `session_new`, `session_compact`, model/thinking, and model-list operations;
  searches across schema, extension, and app found no `extension_command` or
  command-name dispatcher.
- The extension's `session_new` route still uses a fresh command capability when
  present. Without it, only a restart-managed, lifecycle-owning runtime may
  fence ingress, drain accepted delivery, stage sender-scoped `action_ok` plus
  projection reset, dispose normally, and exit through
  `EXIT_FRESH_SESSION = 42`.
- The interactive wrapper and daemon supervisor consume that same exit code and
  omit `--continue` for exactly the successor launch. Later managed restarts
  resume normally.
- The app still sends typed, session-scoped `SessionNew`, correlates
  `action_ok`/`action_error`, clears only after ACK, and tests successor
  hydration plus stale-frame rejection.

Verification evidence:

- `pi-extension`: `corepack pnpm typecheck` passed; the final current-tree
  `corepack pnpm test` passed **60 files / 1098 tests**, with 3 intentional
  skips; `corepack pnpm build` passed.
- An earlier full-suite attempt left the seeded 262145-byte audit fixture
  unchanged at its 40 ms assertion window. This was not waived: the focused
  `src/session/e2e.test.ts` rerun passed all 34 tests, the restart-fresh focused
  set passed all 284 tests, and two subsequent full-suite runs passed. No test
  or production source was changed for the rerun.
- `app`: `flutter analyze` reported no issues; the relevant action repository,
  quick-actions sheet, and quick-actions ViewModel tests passed **46/46** with
  `--exclude-tags e2e --concurrency=2`.
- `bash -n` passed for `pi-restart-loop.sh`, `herdr-start-agents.sh`,
  `wrap-agents.sh`, and `refresh-dist.sh`; the item diff passed
  `git diff --check`.
- The phone-attached wrapped-interactive smoke was not rerun in this headless
  worker and remains explicitly unclaimed above. Per the caller's binding
  close-out procedure, current-tree owning-suite evidence is the implementation
  gate; phone smoke remains operator UAT evidence for final acceptance.

### Review handoff

Implementation verification is green and every child is done, so the feature
advances `implementing -> review`. Effective review weight is `standard`
(caller/autopilot note, matching the project default). This delegated close-out
has an explicit review boundary: the parent autopilot owns the required single
fresh-context feature pass and its finding adjudication.

## Other agent review

- **Invoked because**: this is a cross-component lifecycle contract with a
  rejected-design history.
- **Prior advisory evidence**: the recorded `gpt-5.6-sol` review rejected the
  editor seam and established the constraints retained above; the restart-fresh
  checkpoints also passed the `v0.4.0` release review/gate path.
- **Fixed/active blockers**: the design now reconciles already-shipped child
  work, resolves the Herdr mechanism to wrapper ownership, and makes research
  consumption conditional and dedicated-operation-only.
- **Skipped/degraded**: no new fresh-context design pass was dispatched because
  this delegated worker has no generic subagent or peer-review adapter. Design-
  time advisory review is non-blocking; the caller-mandated standard completion
  review remains required after verification.

## Out of scope

- Generic slash-command invocation, slash-prefixed composer routing, a command
  picker, and the custom-editor or synthetic-stdin seams.
- Retiring `session_new`; daemon, interactive wrapper, app compatibility, and
  the generated protocol all depend on it.
- Implementing or patching an upstream Pi host-operation API.
- Reliable-delivery redesign for the pre-exit `action_ok`.
