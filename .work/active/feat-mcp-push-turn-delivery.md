---
id: feat-mcp-push-turn-delivery
kind: feature
status: active
created: 2026-11-19
updated: 2026-11-20
tags: [pi-extension, docs, research]
---

# MCP push-turn delivery and delivery-mode generalization

## Outcome

Outpost-Pi's MCP mesh layer (`pi-extension/`) supports explicit opt-in push-turn delivery (`--push-deliver` / `OUTPOST_PI_MCP_PUSH_DELIVER=1`) for local peer envelopes while keeping cross-PC (`<pc>:`) and `_relay` envelopes buffered in `get_messages`, generalizes the `agent-network` skill, MCP server instructions, and README around delivery modes instead of Claude-specific framing, and records an empirical Antigravity (`agy`) probe with a Slice 2 design recommendation.

## Scope and exclusions

Included:
- **Part 1 (Delivery-mode docs & instructions):** Generalize `pi-extension/skills/agent-network/SKILL.md`, MCP server `instructions` in `pi-extension/src/mcp/mesh_server.ts`, and `pi-extension/README.md` (plus reconcile the affected assertions in `PROTOCOL.md` and `docs/DECISIONS.md`) around two delivery modes — **push-delivered** and **inbox-drained** — and document the hybrid invariant (local peer envelopes push-delivered & already drained; cross-PC `<pc>:` and `_relay` messages buffered in `get_messages`).
- **Part 2a (Claude push-turn delivery):** Add explicit opt-in `--push-deliver` (default OFF) to `outpost-pi claude` and `--push-deliver` / `OUTPOST_PI_MCP_PUSH_DELIVER=1` to `mesh_server.ts`, with a fail-fast requirement that `--push-deliver` and ambient `OUTPOST_PI_MCP_PUSH_DELIVER=1` strictly require `--outpost-mesh-wake`, preserving all existing authority/drain/local-only guards, and backed by a reusable `PushDeliveryCoordinator` + `PushDeliveryTransport` port with dedicated bounded push queue, 5s `WakeGate` rate cap, byte-capped burst batching, deferred liveness re-check, throwing-`onTransportError` isolation, and safe transport-failure fallback to `get_messages`.
- **Part 2b (`agy` probe & Slice 2 recommendation):** Empirically probe `agentapi send-message` / MCP subprocess env inheritance / `SessionStart` hook env inheritance / `sidecar.json` launch behavior on `agy` 1.5.12 and record the settled findings and Slice 2 design recommendation in `pi-extension/docs/agy-push-delivery.md` and `.work/backlog/idea-agy-push-turn-delivery.md`.

Exclusions:
- No changes outside `pi-extension/`, `PROTOCOL.md`, `docs/DECISIONS.md`, and `.work/`.
- No implementation of the `agy` Slice 2 transport/sidecar/hook runtime yet.
- No wire-protocol changes to broker or relay; no changes to `app/`, `relay/`, `cockpit/`, or `site/`.
- Never inject `--dangerously-skip-permissions`.

## Acceptance evidence

- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` in `pi-extension/` pass cleanly (using repo-local pnpm cache env vars per `pi-extension/CLAUDE.md`).
- Deterministic fake-time tests in `pi-extension/src/mcp/wake.test.ts` (and `inbox.test.ts` for new queue primitives) prove: local-only push routing, zero duplication into `get_messages`, cross-PC/`_relay` isolation in `get_messages`, 5s `WakeGate` rate cap, burst batching within `maxBatchBytes` + deferred liveness re-check for queued remainder, single-flight FIFO async transport serialization, oversized single-message fallback to `get_messages` with body-free pointer, transport-failure rollback into `get_messages` without silent loss, push-queue shedding notice, `onDrain()` not cancelling pending push timers, and `dispose()` teardown preventing late timers.
- Unit tests in `pi-extension/src/extension/command_surface/standalone_cli.test.ts` prove: `--push-deliver` parsing (before/after `[cwd]`, stripped from passthrough), fail-fast rejection when `--push-deliver` is passed without `--outpost-mesh-wake` (even when `--dangerously-load-development-channels` is passed manually), ephemeral MCP config passing `--push-deliver` only when enabled, preservation of `--allowedTools=mcp__outpost-pi-mesh__get_messages`, and absolute non-injection of `--dangerously-skip-permissions`.
- Part 2b empirical probe findings and Slice 2 recommendation recorded below and parked for Slice 2.

## Design

### Approach

- **Dedicated push queue + shared rate cap:** Keep `inbox` (`BoundedInbox<WakeMessage>`) strictly for `get_messages` traffic (cross-PC `<pc>:`, `_relay`, oversized single-message fallback, and push-transport failure fallback). Local messages in push mode enqueue exclusively into a dedicated `pushQueue` (`BoundedInbox<WakeMessage>`, default `1_000` messages / `4 MiB` drop-oldest) so pushed local envelopes never duplicate into `get_messages`.
- **Reusable transport port (`PushDeliveryTransport`):** Define `interface PushDeliveryTransport { deliver(content: string): Promise<void>; }` at the MCP coordinator boundary (ports-and-adapters). `mesh_server.ts` supplies a thin `ClaudeChannelPushTransport` calling `mcp.server.notification({ method: "notifications/claude/channel", params: { content } })`; a future `agy` sidecar adapter plugs into the same interface.
- **Byte-capped burst batching + single-flight FIFO flush:**
  - Extend `BoundedInbox<T>` with `peek()`, `shift()`, and `takeDropped()` so batch extraction preserves internal byte accounting without leaking queue internals.
  - Default batch cap `PUSH_BATCH_MAX_BYTES = 64 * 1024` (64 KiB UTF-8 — safely below Linux `MAX_ARG_STRLEN` 128 KiB for future `agentapi` CLI transport and comfortable for turn notifications).
  - Format pushed envelopes with compact `renderInboxMessage(m)` (preserving linear-in-bytes anti-amplification guarantees) under an explicit header noting the messages are push-delivered and already drained (do not call `get_messages`; reply via `agent_send` echoing `id` as `re`). Include any `pushQueue` drop notice in the same byte budget.
  - If the head message alone exceeds `maxBatchBytes`, pop it from `pushQueue`, move it into `inbox`, and emit a compact body-free pointer (`oversizedPushNudgeContent(msg.from)`) via `transport.deliver` so `maxBatchBytes` is a true ceiling without deadlocking the queue or silently losing the message.
  - Track `inFlight: boolean` so slow async transports never overlap or reorder batches. When `transport.deliver` settles, re-check `!disposed && pushQueue.length > 0` to flush or arm the deferred timer for remaining work.
  - On `transport.deliver` rejection, push every envelope from the failed batch into `inbox` (preserving order and invoking `onTransportError`) so transport failures fall back safely to `get_messages` without silent loss.
  - `onDrain()` (triggered by `get_messages`) is a no-op on `PushDeliveryCoordinator` because draining cross-PC messages from `inbox` must not cancel a deferred push timer for local messages in `pushQueue`.
  - `dispose()` sets `disposed = true` and cancels any armed timer synchronously on `mesh_server.ts` shutdown.

### Adds and retires

- **Adds:**
  - `pi-extension/src/extension/command_surface/standalone_cli.ts`: `PUSH_DELIVER_FLAG` (`"--push-deliver"`), `validateClaudeCliArgs({ meshWake, pushDeliver })`, `pushDeliver` field on `splitClaudeCliArgs`, optional `{ pushDeliver?: boolean }` parameter on `writeEphemeralMcpConfig`.
  - `pi-extension/src/mcp/inbox.ts`: `BoundedInbox.peek()`, `shift()`, `takeDropped()`, boolean return from `push()`.
  - `pi-extension/src/mcp/wake.ts`: `WakeCoordinator.dispose()`.
  - `pi-extension/src/mcp/push_delivery.ts`: `PUSH_BATCH_MAX_BYTES`, `PushDeliveryTransport`, `PushDeliveryCoordinatorOptions`, `createPushDeliveryCoordinator`, `oversizedPushNudgeContent`, `MeshServerOptions`, `parseMeshServerOptions`, `buildMcpInstructions`.
  - `pi-extension/src/mcp/mesh_server.ts`: `--push-deliver` CLI flag and `OUTPOST_PI_MCP_PUSH_DELIVER=1` env var (default OFF), push-mode coordinator wiring, mode-aware MCP instructions.
  - `docs/DECISIONS.md`: reconciled `Extension, not wrapper` entry for `--push-deliver`.
  - `.work/backlog/idea-agy-push-turn-delivery.md`: parked Slice 2 handoff grounded in Part 2b empirical probe findings.
- **Retires:**
  - Claude-only framing ("Claude (MCP) vs. Pi", "on Claude") in `pi-extension/skills/agent-network/SKILL.md`, `pi-extension/src/mcp/mesh_server.ts` instructions, and `pi-extension/README.md` (replaced by generic delivery-mode framing).

### Refusals and hard stops

- **`outpost-pi claude --push-deliver` without `--outpost-mesh-wake` exits 1:**
  - *Threat/failure prevented:* `mesh_server.ts` cannot detect whether Claude enabled dev-channels (`notifications/claude/channel` is silently ignored by an un-opted host). Pushing local envelopes out of `get_messages` without `--outpost-mesh-wake` would silently drop every local message.
  - *User cost:* An operator who manually passes `--dangerously-load-development-channels=...` without `--outpost-mesh-wake` must add `--outpost-mesh-wake` (which already deduplicates an operator-supplied dev-channels flag while preserving drain pre-approval).
  - *Why no degraded path:* Silently downgrading to inbox polling when the operator explicitly requested `--push-deliver` hides misconfiguration; failing fast at CLI parse time before launching Claude gives an immediate actionable fix.

### Implementation difficulty

- **Moderate** on `PushDeliveryCoordinator` (async `inFlight` interleaving, `WakeGate` skew/re-arming, byte-budget accounting for headers + drop notices + oversized messages, and failure rollback to `inbox` without timer leaks on `dispose()`).
- **Low** on CLI arg splitting/validation, `mesh_server.ts` option parsing, and delivery-mode doc generalization.

## Part 2b — Antigravity (`agy`) empirical probe & Slice 2 recommendation

Settled empirical probe record and Slice 2 architecture live in `pi-extension/docs/agy-push-delivery.md` and are parked in `.work/backlog/idea-agy-push-turn-delivery.md`:
- Clean-environment probes (`ANTIGRAVITY_*` stripped before invoking `agy` 1.5.12) confirmed both stdio MCP subprocesses (`mesh_server.js`) and `SessionStart` hooks lack `ANTIGRAVITY_LS_ADDRESS` and `ANTIGRAVITY_CSRF_TOKEN` (`SessionStart` receives only `ANTIGRAVITY_CONVERSATION_ID` + stdin JSON), eliminating direct MCP `agentapi` calls and `SessionStart` credential handoff.
- `agy` CLI exposes no sidecar manager (global `sidecar.json` requires Antigravity 2.0 Desktop's Automations dashboard).
- Split recommendation: **Desktop** → Sidecar UDS Relay + `SessionStart` `0600` `(cwd → conversationId)` binding reusing `PushDeliveryTransport` / `createPushDeliveryCoordinator`; **CLI interactive** → stay inbox-drained (`get_messages`, optional `Stop` hook for mid-turn arrivals); **CLI headless** → wrapper driving `agy --input-format stream-json --output-format stream-json` or `agy acp`.

## Delivery status

Consolidated best-of-arms implementation staged on `main`:
- `pi-extension/skills/agent-network/SKILL.md`, `pi-extension/README.md`, `PROTOCOL.md`, `docs/DECISIONS.md` (delivery-mode framing + hybrid invariant + MCP push-queue retention bounds).
- `pi-extension/src/mcp/inbox.ts`, `pi-extension/src/mcp/wake.ts`, `pi-extension/src/mcp/push_delivery.ts`, `pi-extension/src/mcp/mesh_server.ts` (dedicated `pushQueue`, `PushDeliveryTransport` port, `PUSH_DELIVER_CLI_FLAG`/`PUSH_DELIVER_ENV_VAR` single source of truth, `createPushDeliveryCoordinator` with 5s `WakeGate`, 64 KiB UTF-8 batching, oversized single-message fallback + pointer, single-flight async FIFO serialization, transport-failure rollback to `inbox` with `pendingDropped` preservation and throwing-`onTransportError` isolation, `dispose()` teardown, `--push-deliver` / `OUTPOST_PI_MCP_PUSH_DELIVER=1`, mode-aware MCP instructions).
- `pi-extension/src/extension/command_surface/standalone_cli.ts` (`PUSH_DELIVER_FLAG`, `validateClaudeCliArgs` fail-fast exit 1 when `--push-deliver` or ambient `OUTPOST_PI_MCP_PUSH_DELIVER=1` lacks `--outpost-mesh-wake`, ephemeral MCP config `--push-deliver` wiring, existing authority/drain guards preserved).
- `pi-extension/docs/agy-push-delivery.md` + `.work/backlog/idea-agy-push-turn-delivery.md` (settled Part 2b empirical probe findings & Desktop vs CLI split) + `.work/backlog/idea-broker-cwd-control-char-sanitization.md` (parked follow-up).
- Tests in `pi-extension/src/mcp/inbox.test.ts`, `pi-extension/src/mcp/wake.test.ts`, `pi-extension/src/extension/command_surface/standalone_cli.test.ts`.

