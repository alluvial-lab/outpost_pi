---
id: backlog-mobile-new-button-newsession-no-command-ctx
created: 2026-08-03
updated: 2026-08-26
tags: [app, pi-extension, bug]
status: superseded
superseded_by: feature-mobile-slash-command-invocation (active) — names this item as origin; groom 2026-08-26
---

# Mobile "New" button: "newSession unavailable (no command ctx yet)"

## Symptom (operator, 2026-08-03)

Tapping the **New** button on mobile surfaces the exact error
`newSession unavailable (no command ctx yet)`.

## Pinned code path (quick grep, not a full investigation)

- **Throw site:** `pi-extension/src/actions/handlers.ts` —
  `if (!ctx?.newSession) throw new Error(...)` — the "new session" action
  handler aborts when the command context's `newSession` is absent.
- **Trigger (app):** the mobile "New" quick-action runs
  `ActionName.sessionNew` —
  `app/lib/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart`
  (`_runVoid(ActionName.sessionNew, _repo.…)`) → sends the `sessionNew` action
  to the extension → hits the handler above.
- **Command-context binding (extension):** `bindCommandContext` /
  `_rememberCommandCtx` (`pi-extension/src/index.ts`) and the tracked
  context in `pi-extension/src/session/sdk_session_projection.ts`
  (`bindCommandContext` / `bindReplacementContext`). "no command ctx yet" =
  none of these has bound a context with `newSession` at the moment the action
  fires.

## Confirmed root cause (2026-08-04)

The installed `@earendil-works/pi-coding-agent` 0.80.6 does **not** provide an
`ExtensionCommandContext` to `session_start` or ordinary turn/event handlers.
Its lifecycle is precise:

1. Each run mode calls `AgentSession.bindExtensions(...)` at startup with
   host-owned `commandContextActions` (including `newSession`). Internally this
   calls `ExtensionRunner.bindCommandContext(actions)` **before** emitting
   `session_start`, but that SDK method only stores the action implementations
   inside the runner; it does not expose a command context to extensions.
2. `session_start`, `turn_start`, and all other ordinary hooks are emitted via
   `ExtensionRunner.emit()`, which always passes `createContext()` — the base
   `ExtensionContext`, intentionally lacking `newSession` because the SDK says
   session-control methods are command-only to avoid event-handler deadlocks.
3. The SDK creates an `ExtensionCommandContext` only when
   `AgentSession._tryExecuteExtensionCommand()` invokes a registered extension
   slash command. It also creates a fresh command-capable
   `ReplacedSessionContext` for an already-started replacement's `withSession`
   callback. An ordinary first agent turn does **not** arm this capability.
4. Outpost-Pi's similarly named `bindCommandContext` port is not an SDK startup
   hook. It runs only from `_rememberCommandCtx`, which wraps actual
   `/outpost-pi ...` command handlers, or after a successful replacement via
   `withSession`. Therefore `SdkSessionProjection.commandCtx` is null after a
   fresh process start until an extension command has actually run.

A probe against the installed SDK confirmed the runtime shapes:

```text
session_start  hasNewSession=false
turn_start     hasNewSession=false
command        hasNewSession=true
```

There is no public `ExtensionAPI` method to obtain the runner's command context,
to invoke an extension command programmatically without an LLM turn, or to
replace the host's active `AgentSessionRuntime`. `pi.sendUserMessage()` is not a
back door: the SDK calls `prompt(..., expandPromptTemplates: false)`, explicitly
skipping extension-command dispatch.

The observed handler `throw` is caught by `runAsync`; the wire result is already
a sender-scoped `action_error`, which `ActionsRepository` converts to
`ActionFailure` and the quick-action sheet displays. The defect is therefore
not an uncaught process crash or silent drop: the command is explicitly rejected
and the required fresh session is not created.

## Design options

### A. Add a host-safe SDK session-replacement capability (recommended)

Upstream Pi should expose a public capability for extensions whose external
callbacks need to request a session replacement after startup — for example an
idle-safe `ExtensionAPI.newSession()` or an explicit host-operation gateway.
Simply adding `newSession` to every event context would violate the SDK's stated
deadlock boundary. Once the SDK has a supported operation, Outpost-Pi can bind
it during factory/session startup and keep the existing `withSession` re-arm,
session reset, and daemon behavior.

This is the only option that works uniformly for interactive Pis regardless of
which terminal/process manager launched them.

### B. Extend process-recycle semantics beyond daemons

The daemon path is sound because `RpcChild` and `Supervisor` own both sides of
`EXIT_DAEMON_FRESH_SESSION`: they ACK/reset/exit, then omit `--continue` exactly
once on the next spawn. Interactive processes do not have that contract:

- `scripts/pi-restart-loop.sh` relaunches only after exit 0 plus a hot-reload
  marker, and its fixed args always include `--continue`; exit 42 is treated as
  a crash and stops the loop.
- The other live Pi panes are Herdr-managed. Herdr records each managed Pi's
  exact session path in its session state, so an ordinary restart resumes that
  session rather than creating a fresh one.

Making this reliable requires coordinated wrapper/Herdr work: a distinct
fresh-session restart request, ACK and graceful-shutdown semantics, relaunch
without a resume target, and successor `session_start`/room-meta convergence.
That is cross-subsystem work outside this focused bug's allowed write scope.
An extension-only `process.exit(42)` would stop interactive Pi or resume the old
session and would falsely ACK success.

### C. Improve the unavailable-state UX only (does not fix the use case)

A stable reason code/capability signal could let the app say that a Pi extension
command must run before New is available. The current app already surfaces the
`action_error` text, so this would be UX polish rather than a functional repair;
gating New also directly blocks the reported post-restart use case. Do not ship
this alone as the bug fix.

## Investigation outcome

Stopped without code changes. A correct repair is larger than a focused
handler/projection patch: it needs either a supported Pi SDK operation or a
coordinated interactive process-manager fresh-session contract. No known-red
regression test was committed; the existing handler test already proves the
current no-context `action_error`, while an acceptance test requiring a created
session cannot pass until one of the designs above is selected. The daemon
`EXIT_DAEMON_FRESH_SESSION` path remains unchanged.

Verification of the unchanged behavior:

- Installed-SDK probe: `session_start=false`, `turn_start=false`, registered
  extension command=true for `typeof ctx.newSession === "function"`.
- `./node_modules/.bin/vitest run src/actions/handlers.test.ts
  src/session/sdk_session_projection.test.ts`: 70 passed.
- `./node_modules/.bin/vitest run src/extension.test.ts -t "daemon session_new
  ACKs and resets before exit 42"`: 1 passed (212 unrelated tests skipped by
  the name filter).
- A full `pnpm test` attempt completed all 55 test files with 963 passed / 3
  skipped, then exited non-zero on the suite's existing environment-sensitive
  UDS cleanup race (`chmod .../.pi/remote/locks/*.sock`: `ENOENT`). No product
  test failed, and no test was weakened or skipped to hide it.

## Spike finding

### Verdict: PARTIAL

There is **no supported extension prompt/command submission API** in installed
Pi SDK 0.80.6. `ExtensionFactory` receives only `ExtensionAPI`
(`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts:839-998,1060`),
whose only message ingress methods are `sendMessage` and `sendUserMessage`
(`types.d.ts:895-905`); the host-level `AgentSession.prompt()` exists, but only
on an `AgentSession` owned by the embedding host
(`dist/core/agent-session.d.ts:168,343`), and the active host session is not
exposed to the extension.

There is, however, a **TUI-only indirect submission seam** through the public
custom-editor API. An extension may install and retain an `EditorComponent` via
`ctx.ui.setEditorComponent()` (`types.d.ts:165-172`). `EditorComponent` publicly
has `onSubmit?: (text) => void`
(`@earendil-works/pi-tui/dist/editor-component.d.ts:17-18`), and interactive Pi
wires that callback to the default editor's real submission handler after the
factory returns (`dist/modes/interactive/interactive-mode.js:1827-1839`). Calling
the retained component's `onSubmit?.("/new")` therefore enters the exact handler
that recognizes `/new` (`interactive-mode.js:2168-2171`) and calls
`runtimeHost.newSession()` (`interactive-mode.js:4868-4877`). This is not a
documented command API; it is a UI-component callback seam backed by current
InteractiveMode implementation.

Minimal shape (only after the factory has returned and Pi has wired
`onSubmit`):

```ts
import { CustomEditor, type ExtensionContext } from "@earendil-works/pi-coding-agent";

let commandEditor: CustomEditor | undefined;

function installTuiSubmitBridge(ctx: ExtensionContext): void {
  if (ctx.mode !== "tui") return;
  ctx.ui.setEditorComponent((tui, theme, keybindings) => {
    commandEditor = new CustomEditor(tui, theme, keybindings);
    return commandEditor;
  });
}

// Later, from an idle external callback — not while the factory itself runs:
commandEditor?.onSubmit?.("/new");
```

A throwaway pseudo-TTY probe loaded a minimal extension into the **installed
0.80.6 CLI**, retained a custom editor, called `onSubmit("/new")`, observed the
replacement lifecycle, then submitted `/quit` through the same seam:

```text
session_start reason=startup mode=tui
submit command=/new wired=true
session_start reason=new mode=tui
submit command=/quit wired=true
```

The TUI transcript also contained `New session started`. A second throwaway
probe showed that `process.stdin.emit("data", "/new\r")` reaches the same parser
in TUI mode (`session_start reason=new` observed). That works because Pi's TUI
attaches a `data` listener to `process.stdin`
(`@earendil-works/pi-tui/dist/terminal.js:74-83,110-132,148-150`) and the editor
submission handler owns built-in slash parsing
(`interactive-mode.js:2075-2207`). This is an even less supportable Node
`EventEmitter` injection hack: `stdin` is not a writable extension API, the
synthetic event is process-global and focus/key-encoding sensitive, and it has
no completion contract.

### Candidate inventory

- **`pi.sendUserMessage` — no.** Its implementation deliberately calls
  `prompt(..., { expandPromptTemplates: false, source: "extension" })`, skipping
  extension-command dispatch and all template/skill expansion
  (`dist/core/agent-session.js:1085-1113`). A slash string becomes an agent
  prompt. Installed docs even contain a contradictory `sendUserMessage("/reload-runtime")`
  example (`docs/extensions.md:1307-1315`); the installed implementation is the
  authoritative behavior.
- **`pi.sendMessage({triggerTurn:true})` — no.** It constructs a custom message
  and calls `_runAgentPrompt` directly (`agent-session.js:1047-1069`), bypassing
  prompt and command parsing.
- **`ctx.ui.setEditorText` / `pasteToEditor` — fill only.** They are exposed in
  the types (`types.d.ts:128-132`), but TUI maps them to `editor.setText` /
  `editor.handleInput(paste)` without submitting
  (`interactive-mode.js:1673-1675`). `ctx.ui.onTerminalInput` is listener-only
  (`types.d.ts:76-77`), not an emitter.
- **`ctx.ui.setEditorComponent` + retained `onSubmit` — yes, TUI only, indirect.**
  This is the positive probe above. RPC implements `setEditorComponent()` as a
  no-op (`dist/modes/rpc/rpc-mode.js:193-201`; also `docs/rpc.md:1068-1073`).
- **`pi.registerCommand` / `pi.getCommands` — registration/discovery only.**
  `getCommands()` has no invoke operation (`types.d.ts:923`), and built-in TUI
  commands are omitted and do not execute through host `prompt`
  (`docs/extensions.md:1518-1549`; `docs/rpc.md:781-800`).
- **`ExtensionCommandContext` — direct session control, but command-only.** It
  contains `newSession`, `fork`, `switchSession`, and `reload`
  (`types.d.ts:246-284`), while ordinary events are emitted with base
  `createContext()` (`dist/core/extensions/runner.js:420-488,531-534`). Pi creates
  the command context only after matching an extension command
  (`agent-session.js:903-914`). `ReplacedSessionContext` adds message methods but
  is only supplied after an already-authorized replacement (`types.d.ts:287-296`).
- **`pi.events` — no host dispatch.** It is a generic extension-to-extension
  `EventEmitter` (`types.d.ts:998`; `dist/core/event-bus.js:3-18`), with no Pi
  input/command listener.
- **Host SDK / RPC — closest supported alternatives, but not available as the
  active extension host.** An embedding owner can call `AgentSession.prompt()`;
  it recognizes registered extension commands when expansion is enabled
  (`agent-session.js:776-788,903-914`), not built-in TUI commands. An external
  RPC owner writes JSONL to child stdin; RPC `prompt` calls `session.prompt` with
  source `rpc` (`dist/modes/rpc/rpc-mode.js:297-318`) and has a separate supported
  `new_session` operation (`rpc-mode.js:332-338`).

### Cockpit/control-frame trace

Current Cockpit does not write a literal `CTRL_PREFIX`; it wraps the canonical
`outpost_pi_control` envelope in an RPC `{type:"prompt", message:...}` frame
(`cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:405-429`) and writes that
JSONL to the child process's stdin (`pi_rpc_process.dart:269-277`). The daemon
supervisor uses the same external-child shape for ordinary prompts
(`pi-extension/src/daemon/rpc_child.ts:314-325`). RPC stdin is decoded externally
and forwarded as `session.prompt(..., source:"rpc")`
(`dist/modes/rpc/rpc-mode.js:297-305,624-626`); Outpost-Pi's `input` hook then
parses the structured envelope or legacy NUL prefix and returns
`{action:"handled"}` (`pi-extension/src/index.ts:203-214,1253-1275`). Thus this
control path is an **external RPC-stdin writer**, not an in-process ExtensionAPI
command channel. In-process synthetic `stdin.emit` can hit the listener, as the
probe showed, but is unsupported and must use the mode's framing (raw terminal
keys in TUI; JSONL in RPC).

### Conditions and caveats

The custom-editor bridge works only when `ctx.mode === "tui"`, after the editor
factory has returned and host wiring is complete, and should be invoked only at
an idle/lifecycle-safe boundary. It replaces or wraps the user's editor, can
conflict with other custom-editor extensions, exposes a `void` callback rather
than an awaitable success/error result, and becomes stale across `/new`,
`/resume`, `/fork`, and `/reload`; success must be confirmed by the successor
`session_start`. It cannot provide a uniform daemon/RPC implementation, and
arbitrary slash strings are limited to commands recognized by the interactive
handler.

**Fix viability:** Mobile “New = native `/new`” is achievable in-process for an
interactive TUI Pi only through this indirect editor callback (or an unsupported
synthetic-stdin hack); a supported, mode-independent fix still needs an upstream
submit/host-operation API, while daemon mode should use its explicit RPC/restart-fresh
contract.
