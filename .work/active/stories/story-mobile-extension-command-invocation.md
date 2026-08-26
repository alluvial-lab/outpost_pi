---
id: story-mobile-extension-command-invocation
kind: story
stage: done
tags: [app, pi-extension, research]
parent: feature-mobile-slash-command-invocation
depends_on: []
release_binding: null
gate_origin: null
provenance: synthesis
created: 2026-08-04
updated: 2026-08-26
research_dials:
  scope_authority: pre-registered
  verification_rigor: standard
  intent: verify the Pi SDK surface for invoking extension/host operations from mobile (verify-first, feeds parent feature design)
  output_kind: findings recorded in this item body, consumed by parent feature design
---

# Extension-command invocation from mobile (verify-first)

A verify-first item under `feature-mobile-slash-command-invocation`. The
extension **owns** its registered commands (`/outpost-pi …` via
`createCommandSurface`/`registerOutpostPiCommands`) — unlike pi-native
session-control ops, the handler logic lives in the extension. Question: can
those commands be invoked from mobile **without** the `ExtensionCommandContext`
gate (i.e., without needing a pre-existing slash-command to arm the context)?

## Verify (read-first; produce a finding before any implementation)

1. Read the extension's command handlers (`pi-extension/src/extension/command_surface/**`)
   — for each `/outpost-pi` command, what context does its handler actually use?
   Base-`ExtensionContext` methods (available from `session_start`), or
   `ExtensionCommandContext`-only methods (`newSession`/`fork`/`reload`/`waitForIdle`)?
2. If a command's handler uses only base-context methods → it's callable from the
   mobile path without the gate (the extension invokes its own handler with the
   event/session context). If it uses command-context-only methods → it's gated
   (same class of problem as `/new`).
3. Produce a per-command table: `{command, ctx-required, mobile-invokeable?}`.

## Change (only if the verify shows a clean path)

- A wire action (e.g. `extension_command { command, args }`) the app sends; the
  extension dispatches to its own handler with the available (base) context for
  commands that don't need the command-context.
- App: a way to issue extension commands (picker entry, or quick-actions).

## Acceptance

- [x] Per-command verify table recorded in this body.
- [ ] If a clean path exists for some commands: a wire action + app entry +
      round-trip test for at least one; if not: documented why (gated), parked.
      **Research close:** a clean subset exists; implementation belongs to the
      parent feature's design/implementation flow, not this verify-only story.

## Ordering

`depends_on: []` (independent verify). May yield a clean capability for a subset
of extension commands, or confirm they're gated (park).

## Findings

### Executive verdict

The premise that extension commands are TUI-only is false for the pinned SDK.
Outpost-Pi pins `@earendil-works/pi-coding-agent` **0.80.6**
(`pi-extension/package.json:80-82`). [pi-sdk-0-80-6-package]{1} In that
version, an SDK host invokes any registered **extension** command by calling
`AgentSession.prompt("/<command> <args>")`; Pi resolves the registration,
constructs a real `ExtensionCommandContext`, and awaits the handler before the
normal input/LLM path (`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js:769-790,901-924`).
The RPC host exposes the same route: RPC `prompt` delegates to
`session.prompt(...)` and binds all command-context actions
(`.../dist/modes/rpc/rpc-mode.js:227-258,297-317`).
[pi-sdk-0-80-6-agent-session]{1} [pi-sdk-0-80-6-rpc-mode]{1}

There is **no direct named** `ExtensionAPI.invokeCommand()` or
`executeCommand()` method. `ExtensionAPI.getCommands()` is discovery only
(`.../dist/core/extensions/types.d.ts:874-876,922-923`); the general execution
surface is `AgentSession.prompt`, or RPC `prompt` for an out-of-process host.
The RPC union likewise has `prompt`, dedicated operations, and `get_commands`,
but no named invoke-command frame
(`.../dist/modes/rpc/rpc-types.d.ts:15-129,131-142`).
[pi-sdk-0-80-6-extension-types]{1} [pi-sdk-0-80-6-rpc-types]{1}

That does **not** mean the existing app-to-extension callback can call the
registered command through its captured `pi: ExtensionAPI`. Extension-side
`pi.sendUserMessage()` reaches `AgentSession.sendUserMessage()`, which
explicitly calls `prompt(..., { expandPromptTemplates: false })` to skip command
handling (`.../dist/core/agent-session.js:1079-1113`). Therefore, sending
`"/outpost-pi status"` through the extension's existing mobile wake path would
be an LLM/user message, not a command dispatch. [pi-sdk-0-80-6-agent-session]{1}

### Dedicated host/session operations

The installed surface has three distinct capability levels:

1. **Base extension context:** `ExtensionContext` exposes `abort`, `shutdown`,
   and callback-style `compact`, so these are available from `session_start`
   and other event contexts (`.../dist/core/extensions/types.d.ts:211-241`).
2. **Command context only:** `waitForIdle`, `newSession`, `fork`,
   `navigateTree`, `switchSession`, and `reload` exist only on
   `ExtensionCommandContext` (`.../dist/core/extensions/types.d.ts:243-282`).
   Pi keeps them out of ordinary event handlers because those calls can
   deadlock there (`.../docs/extensions.md:1071-1075`).
3. **Owning host:** code that owns `AgentSessionRuntime` can call
   `runtime.newSession()/switchSession()/fork()` directly, and RPC exposes
   dedicated `new_session`, `compact`, model, thinking, switch, fork, and clone
   commands. Since 0.65.0, session replacement belongs to
   `AgentSessionRuntime`, not `AgentSession`
   (`.../CHANGELOG.md:1419-1433,1497-1500`).

[pi-sdk-0-80-6-extension-types]{1} [pi-sdk-0-80-6-extensions-docs]{1}
[pi-sdk-0-80-6-changelog]{1}

For Outpost-Pi, this preserves the existing distinction: a mobile callback
inside the extension does not own the SDK runtime and cannot obtain
`newSession` from a base event context. A truly external RPC host can use the
dedicated RPC operation. This is separate from extension-owned `/outpost-pi`
operations, whose actual handlers do not use command-only session controls.

### Outpost-Pi per-command verification

The current registry has twenty subcommands plus the root command
(`pi-extension/src/index.ts:1813-1852`). Its Pi-facing adapter is typed with
`ExtensionCommandContext`, and `runWithCtx` captures that real command context,
but the concrete operations receive only base `ExtensionContext` subsets,
principally `ui` and sometimes `cwd`
(`pi-extension/src/index.ts:1784-1810,1895-1947,2095-2129,2923-2971`).
[outpost-pi-command-registry]{1} [outpost-pi-command-adapters]{1}

“Mobile-invokable” below means **the operation is not blocked by an
`ExtensionCommandContext`-only SDK capability after a typed mobile dispatcher
and mobile result sink are added**. It does not claim that today's wire already
has such a message.

| Command | Actual context required | Mobile-invokable? | Non-context caveat |
|---|---|---:|---|
| `/outpost-pi` | base `ui + cwd` | Conditional | Clean for configured installs; first run enters the setup wizard. |
| `/outpost-pi setup` | base `ui + cwd` | Conditional | Requires interactive `ui.select`; needs a real mobile setup flow, not a notification-only adapter. |
| `/outpost-pi hot-reload` | base `ui` | No in daemon mode | Handler explicitly disables itself when `OUTPOST_PI_DAEMON=1`; interactive process only. |
| `/outpost-pi status` | base `ui` | Yes | Needs structured/mobile output instead of `ui.notify` text. |
| `/outpost-pi stop` | base `ui` | Yes | Destructive disconnect; require explicit confirmation/policy. |
| `/outpost-pi pair` | base `ui + cwd` plus mode check | No on the current daemon path | Non-TUI calls are rejected unless the private pair-code-file seam is configured. Pairing needs a purpose-built secure flow. |
| `/outpost-pi devices` | base `ui` | Yes | Return structured device records rather than formatted notification text. |
| `/outpost-pi revoke` | base `ui + cwd` | Yes | Security-sensitive; confirmation and self-revocation behavior must be explicit. |
| `/outpost-pi set-relay` | base `ui` | Yes | Configuration mutation; validate structured URL input at ingress. |
| `/outpost-pi peers` | base `ui` | Yes | Return structured peer inventory rather than formatted text. |
| `/outpost-pi create` | base `ui` | Yes | Filesystem/supervisor mutation; use structured args and authorization policy. |
| `/outpost-pi remove` | base `ui` | Yes | Destructive supervisor mutation; require confirmation. |
| `/outpost-pi daemons` | base `ui` | Yes | Return structured fleet state. |
| `/outpost-pi daemon start` | base `ui` | Yes | Supervisor must be reachable. |
| `/outpost-pi daemon stop` | base `ui` | Yes | Destructive process operation; require confirmation. |
| `/outpost-pi daemon restart` | base `ui` | Yes | Disruptive process operation; require confirmation. |
| `/outpost-pi daemon status` | base `ui` | Yes | Return structured fleet state. |
| `/outpost-pi daemon send` | base `ui` | Yes | This is already a supervisor-to-child RPC prompt path; retain prompt/session targeting and delivery semantics. |
| `/outpost-pi cron` | base `ui` | Yes | Mutating subcommands need structured validation and confirmation policy. |
| `/outpost-pi install` | base `ui` | Context-clean, not recommended | Privileged host-service installation is unsuitable for a generic remote picker; may require local OS/admin interaction. |
| `/outpost-pi uninstall` | base `ui` | Context-clean, not recommended | Privileged/destructive host-service removal should remain local unless separately designed. |

The handler declarations substantiate the table:
`local_mesh_commands.ts:39-59,94-191,208-263`,
`pairing_commands.ts:5-18`, `pairing_coordinator.ts:216-220,272-280`,
`daemon_commands.ts:7,25-232`, `cron_commands.ts:16-140`,
`service_commands.ts:4-65`, and `relay_commands.ts:6-37`.
None calls `waitForIdle`, `newSession`, `fork`, `navigateTree`, `switchSession`,
or `reload`. [outpost-pi-local-mesh-commands]{1}
[outpost-pi-pairing-commands]{1} [outpost-pi-pairing-command-handler]{1}
[outpost-pi-daemon-command-handler]{1} [outpost-pi-cron-command-handler]{1}
[outpost-pi-service-command-handler]{1} [outpost-pi-relay-command-handler]{1}

### What the daemon/child RPC layer can reach

`RpcChild` can already write an arbitrary Pi RPC `prompt` frame to the child's
stdin (`pi-extension/src/daemon/rpc_child.ts:314-330`). Thus a supervisor-side
caller could send `/outpost-pi status`, and Pi 0.80.6 would invoke the registered
handler with a real command context. However, this adapter is explicitly
fire-and-forget: it does not await the prompt response, and child stdout is only
parsed for streaming-busy transitions and correlated `get_state` replies
(`rpc_child.ts:9-23,353-402`). It therefore cannot currently return command
success, formatted notifications, extension UI requests, or structured results
to the mobile owner channel. [outpost-pi-rpc-child-current]{1}

{inferred: topology} The live app path is also different: app traffic arrives
through the relay into the extension already running inside that child; it does
not naturally re-enter the supervisor's stdin RPC channel. Reusing RPC command
invocation would require a new correlated child-RPC request/result bridge. That
is possible but larger and more indirect than dispatching extension-owned
operations in-process.

### Design input for the parent feature

1. **Do not fabricate an `ExtensionCommandContext` and do not invoke the
   registered handler by casting a base event context.** The current command
   adapter captures the real command context for later `session_new` capability
   reuse (`pi-extension/src/index.ts:1784-1810`). A fake context would falsely
   arm that capability cache.
2. **Extract/reuse an extension-owned operation registry** whose handlers accept
   a narrow operation context/result port. Register thin Pi slash-command
   adapters over it, and add a separately typed mobile adapter over an explicit
   allowlist. This preserves one implementation without pretending mobile owns
   Pi's command context.
3. **Return structured results.** Nearly every current handler reports through
   `ctx.ui.notify`; raw RPC invocation would emit `extension_ui_request` frames,
   and direct mobile dispatch otherwise has nowhere reliable to send output.
   Mobile operations should return typed payloads/errors which the slash adapter
   can render and the owner-channel adapter can encode.
4. **Do not expose an unrestricted command string.** Context-clean does not mean
   remotely appropriate: revoke, stop/remove/restart, cron mutation, and service
   install/uninstall have materially different authorization/confirmation
   requirements. Derive wire variants and dispatch from the curated operation
   registry.
5. **Keep built-in and extension command claims separate.** The current
   `PROTOCOL.md:317-321` claim remains directionally correct for built-in
   interactive commands, which are absent from `get_commands` and do not execute
   through RPC prompt, but it is stale/incomplete for extension-registered
   commands in SDK 0.80.6. [outpost-pi-protocol-command-claim]{1}
   [pi-sdk-0-80-6-rpc-docs]{1}

### Changes visible in the installed SDK history

- 0.32.2 made extension-command execution through SDK/RPC `prompt` immediate and
  streaming-aware (`CHANGELOG.md:3624-3636`).
- 0.50.2 added headless RPC `get_commands`; 0.51.3 added
  `ExtensionAPI.getCommands()` discovery “for invocation via `prompt`”
  (`CHANGELOG.md:2628-2642,2422-2436`).
- 0.65.0 moved new/switch/fork from `AgentSession` to
  `AgentSessionRuntime` (`CHANGELOG.md:1419-1433`).
- 0.69.0 hardened replacement lifecycle: old captured `pi`/command contexts are
  stale after replacement, and post-switch work belongs in `withSession`
  (`CHANGELOG.md:1075-1101`). [pi-sdk-0-80-6-changelog]{1}

### Contradictions

1. The declaration comment at
   `.../dist/core/extensions/types.d.ts:1170-1173` says command-context actions
   are only needed for interactive mode, but the installed RPC runtime actually
   binds them at `.../dist/modes/rpc/rpc-mode.js:227-258`. Relationship:
   **contradicts**. Runtime behavior plus the installed RPC documentation wins
   for 0.80.6; treat the declaration comment as stale prose.
2. The installed extension docs show a tool queuing `/reload-runtime` through
   `pi.sendUserMessage()` (`.../docs/extensions.md:1295-1317`), but the installed
   runtime explicitly disables command handling in `sendUserMessage()`
   (`.../dist/core/agent-session.js:1107-1113`). Relationship: **contradicts**.
   Do not rely on extension-internal `sendUserMessage` as a command loopback
   without a focused upstream/runtime test proving otherwise.
3. Current `PROTOCOL.md:317-321` says there is no generic SDK built-in command
   API. Relationship: **qualifies**, not a full contradiction. There is still no
   direct named invoke method and built-in TUI commands remain excluded, but
   extension commands are externally invokable through `AgentSession.prompt` /
   RPC `prompt`. [pi-sdk-0-80-6-extensions-docs]{1}
   [pi-sdk-0-80-6-rpc-docs]{1} [pi-sdk-0-80-6-agent-session]{1}

### Disconfirming analysis

The engagement searched the installed declarations, runtime implementation,
RPC union/dispatcher, docs, changelog, and Outpost-Pi's child adapter for a
public `invokeCommand`/`executeCommand`, a command-context method on base event
contexts, or a working extension-side command loopback. None exists. The main
disconfirming evidence against the positive verdict is that `ExtensionAPI`
does not expose `AgentSession.prompt` and `sendUserMessage` disables command
expansion. That narrows the verdict to **external SDK/RPC hosts can invoke
registered commands; in-extension mobile callbacks should invoke extracted
operations, not attempt SDK command dispatch**.

### Verification

- **Citation lint:** `25 resolved/non-broken`, `0 broken`, `0 thin`. The ten
  version-number pattern warnings were categorically spot-checked: every SDK
  version claim is adjacent to the pinned manifest or installed changelog
  attestation.
- **Adversarial jobs (a-h):** semantic chain walk, uncited-claim scan,
  contradiction coherence, relevance weighting, quote context, analytical-tier
  inheritance, line-reference validation, and substantive attestation depth all
  passed after splitting the initial multi-file handler/docs attestations into
  one source file per attestation. The adversarial verdict is **APPROVED**. The
  harness did not expose a child-agent dispatch tool to this already-delegated
  worker, so the fresh-context mechanism degraded transparently to a separate
  skeptical second pass in this context; no unresolved finding remains.
- **Final spot-check:** re-read the installed manifest, context declarations,
  `AgentSession.prompt` and `sendUserMessage` implementations, RPC union and
  dispatcher, all twenty command specs, handler signatures, and `RpcChild`
  request/result behavior. The executive verdict and table match those sources.

### Engagement record

- Registered dials honored: `scope_authority: pre-registered`,
  `verification_rigor: standard`, verify-first intent, findings-in-item output.
- Decision relevance: determines whether the parent designs a generic SDK
  command bridge, a direct extension-operation adapter, or parks the feature.
- Remaining registration: consumer
  `feature-mobile-slash-command-invocation`; temporal contract = point-in-time
  verification against pinned SDK 0.80.6; primitives extended/opted out = none;
  analytical artifact = commissioning-item findings.
- Fan-out: focused light path, one facet. The pre-registered framing was retained
  because SDK types/runtime, RPC reachability, child reachability, and handler
  context use are all evidence layers of the same invocation decision rather
  than independently synthesizable questions.
- Substrate check: no overlapping `.research/analysis/` artifact found. The
  existing protocol claim was used as a proposition to test, not as a source of
  SDK truth.
- Verification gates: citation lint, adversarial read, and final categorical
  spot-check passed; transition completed `findings-complete -> done`.
- Research output: this `## Findings` section; attestations under
  `.research/attestation/pi-sdk-0-80-6-*.md` and the cited
  `.research/attestation/outpost-pi-*.md` source attestations.
- Acquisition offgas: none. Installed declarations, runtime, docs, changelog,
  and local source were available; no load-bearing source remained inaccessible.
