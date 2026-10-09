#!/usr/bin/env node
/**
 * MCP server that bridges Claude Code to the outpost-pi agent mesh.
 *
 * Spawned by Claude Code as an MCP server subprocess (stdio).
 * Joins the mesh through the shared `MeshNode` abstraction — the SAME
 * composition the Pi extension uses — so Claude is a first-class mesh
 * participant: it can lead the local UDS broker when no Pi/daemon is up,
 * and (as leader) bring up its own cross-PC relay bridge with its own
 * Pi-key. As a follower it rides the existing leader's bridge.
 *
 * Launched by `outpost-pi claude` (registers this in Claude's local MCP
 * scope). Args: [--cwd <path>] [--name <agentName>] [--no-bridge]
 * Env: OUTPOST_PI_MCP_CWD, OUTPOST_PI_MCP_NAME
 *
 * Lock ownership: this endpoint takes the (cwd, name)-scoped lock — several
 * agents (Pi and/or Claude) may share a folder under distinct names; when
 * the folder's default name is already held, this endpoint coexists under a
 * `#N`-suffixed name instead of failing. No OUTPOST_PI_MCP_CWD pointing at
 * a sibling directory is needed to run a Claude agent beside a resident Pi.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { MeshNode } from "../session/mesh_node.js";
import { loadLocalConfig, defaultAgentName, localConfigExists } from "../session/local_config.js";
import { BoundedInbox, jsonByteSize, renderInboxMessage } from "./inbox.js";
import { WAKE_MIN_INTERVAL_MS, WakeGate, createWakeCoordinator, wakeNudgeContent } from "./wake.js";
import { sessionSockPath, sessionAuditPath, LOCAL_SESSION_NAME } from "../session/global_config.js";
import { resolveRelayUrl } from "../config.js";
import { acquireCwdLock, acquireUniqueNamedCwdLock, type AcquiredLock } from "../session/cwd_lock.js";
import { UUID_RE as ENVELOPE_ID_RE } from "../session/envelope.js";
import { realpathSync } from "node:fs";

// ── Args / config ─────────────────────────────────────────────────────────────

const _argv = process.argv.slice(2);
// This agent's folder = the dir the `claude` session was launched in, which
// Claude sets as this subprocess's `process.cwd()`. We deliberately do NOT use
// CLAUDE_PROJECT_DIR: that's the git repo root, which would collapse every
// monorepo subproject (app/, relay/, …) into one identity + one lock. The
// `outpost-pi claude` launcher therefore registers us WITHOUT a baked `--cwd`,
// so one shared local-scope entry self-identifies per session. `--cwd` and
// OUTPOST_PI_MCP_CWD remain as explicit overrides (tests / manual launches).
let _cwd = process.env["OUTPOST_PI_MCP_CWD"] ?? process.cwd();
let _nameOverride = process.env["OUTPOST_PI_MCP_NAME"];
let _bridgeEnabled = true;

for (let i = 0; i < _argv.length; i++) {
  if (_argv[i] === "--cwd" && _argv[i + 1]) { _cwd = _argv[++i]!; }
  else if (_argv[i] === "--name" && _argv[i + 1]) { _nameOverride = _argv[++i]; }
  else if (_argv[i] === "--no-bridge") { _bridgeEnabled = false; }
}

const _cfg = loadLocalConfig(_cwd);
const AGENT_NAME = _nameOverride ?? _cfg.agent_name ?? defaultAgentName(_cwd);
// Platform-aware (plan/40): POSIX → broker.sock file; Windows → named pipe.
const BROKER_SOCK = sessionSockPath(LOCAL_SESSION_NAME);
const AUDIT_PATH = sessionAuditPath(LOCAL_SESSION_NAME);

// ── Incoming message buffer ───────────────────────────────────────────────────

interface IncomingMsg {
  from: string;
  body: unknown;
  id: string;
  re: string | null;
  at: string;
}

const inbox = new BoundedInbox<IncomingMsg>(jsonByteSize);

// ── Wake wiring (policy lives in wake.ts; this is the server-side adapter) ───

const wakeGate = new WakeGate(WAKE_MIN_INTERVAL_MS);
let _deferredWakeTimer: ReturnType<typeof setTimeout> | null = null;
const wakeCoordinator = createWakeCoordinator(
  inbox,
  wakeGate,
  (from) => {
    // Transport errors only: an un-opted client silently ignores custom
    // notification methods, so this catch can NEVER signal "wake off" — the
    // server cannot detect whether the session runs the dev channel.
    void mcp.server.notification({
      method: "notifications/claude/channel",
      params: { content: wakeNudgeContent(from) },
    }).catch((err: unknown) => {
      logErr(`wake notification transport error: ${String(err)}`);
    });
  },
  {
    arm: (delayMs, fire) => {
      const t = setTimeout(fire, delayMs);
      t.unref?.();
      _deferredWakeTimer = t;
    },
    cancel: () => {
      if (_deferredWakeTimer) { clearTimeout(_deferredWakeTimer); _deferredWakeTimer = null; }
    },
  },
);

// ── Mesh node ─────────────────────────────────────────────────────────────────

// Diagnostics go to STDERR — stdout is the JSON-RPC channel, so writing there
// would corrupt the MCP protocol. Claude Code captures an MCP server's stderr
// into its mcp-logs, which is where these land for debugging.
function logErr(msg: string): void {
  process.stderr.write(`[outpost-pi-mesh ${isoNow()}] ${msg}\n`);
}

const relayResolution = resolveRelayUrl();
const relayBridgeEnabled = _bridgeEnabled && relayResolution.source !== "unconfigured";
if (_bridgeEnabled && !relayBridgeEnabled) {
  logErr(
    "Relay bridge disabled: relay not configured. Run /outpost-pi set-relay <url>. " +
    "The local mesh remains available.",
  );
}

// Survive stray async failures. This process runs background work (relay WS
// churn, UDS failover, the MCP SDK) whose errors previously had NO global
// handler — a single unhandled rejection or exception silently killed this
// stdio subprocess, and Claude surfaced the MCP as "disconnected" with no
// trace. None of that background work is fatal to serving tools over stdio, so
// log loudly and keep running instead of dying. (We intentionally do NOT
// process.exit here: the tools stay available even if the mesh is degraded.)
process.on("unhandledRejection", (reason) => {
  logErr(`unhandledRejection: ${reason instanceof Error ? (reason.stack ?? reason.message) : String(reason)}`);
});
process.on("uncaughtException", (err) => {
  logErr(`uncaughtException: ${err.stack ?? err.message}`);
});

// Canonicalize so the (cwd, name) the broker keys us by matches roomIdForCwd
// and the Pi extension's own register (symlinked cwds map to one identity).
let _canonCwd = _cwd;
try { _canonCwd = realpathSync(_cwd); } catch { /* cwd missing — use raw path */ }

// The MeshNode is constructed LAZILY, after the lock walk decides this
// endpoint's actual identity: the cwd lock is (cwd, name)-scoped and may
// resolve to a suffixed name (`agent#2`) when the requested name is held by
// a live peer (e.g. a resident Pi agent under the folder's default name).
// Registering under the LOCKED name keeps the lock identity and the broker
// address in lockstep — the same invariant the Pi extension's `/outpost-pi`
// maintains through its `lockedName`.
let mesh: MeshNode | null = null;
let _meshName: string | null = null;

let meshReady = false;
// When the mesh isn't joined, this explains why (folder busy / connecting), so
// the tools return something actionable instead of a generic "not connected".
let degradedReason = "connecting to the mesh…";

// ── MCP server setup ──────────────────────────────────────────────────────────

const mcp = new McpServer(
  { name: "outpost-pi-mesh", version: "0.4.3" },
  {
    capabilities: { experimental: { "claude/channel": {} } },
    instructions: [
      `You are connected to the outpost-pi agent mesh (requested name "${AGENT_NAME}"; when the folder already hosts a same-named agent, your live name carries a #N coexistence suffix — confirm your exact address via list_peers).`,
      "At the start of each turn call get_messages to check for incoming messages from other agents.",
      "Use list_peers to discover available agents.",
      "Use agent_send to send messages — pass the exact address returned by list_peers (form `<cwd>@<name>`, `<pc>:` prefix cross-PC) VERBATIM; never build one by hand.",
      'Use "broadcast" as the target to send to all peers in your folder (cwd) at once.',
      "Follow the agent-network protocol (in your system prompt) for the full details (ACK statuses, replies via re, `<cwd>@<name>` addresses, cross-PC `<pc>:` prefix).",
    ].join("\n"),
  },
);

function notReady() {
  return {
    content: [{ type: "text" as const, text: `Mesh not available yet — ${degradedReason}` }],
    isError: true,
  };
}

/** Best-effort in-channel warning (MCP `logging/message`): clients that
 *  surface server log notifications see contention and identity decisions
 *  WITHOUT a tool call. Claude Code does not record an MCP server's stderr,
 *  so stderr alone left lock-contention failures invisible — the client saw
 *  a healthy handshake and then "not connected" with no diagnostic. Un-opted
 *  clients silently ignore the notification and transport errors land on
 *  stderr; the degraded tool results remain the always-available floor. */
function warnChannel(data: string): void {
  void mcp.server.sendLoggingMessage({ level: "warning", data }).catch((err: unknown) => {
    logErr(`logging notification transport error: ${String(err)}`);
  });
}

mcp.registerTool("list_peers", {
  description: "List all agents currently in the mesh (local + remote PCs).",
  inputSchema: {},
}, async () => {
  if (!meshReady || mesh === null) return notReady();
  try {
    const peers = await mesh.listPeers();
    return { content: [{ type: "text" as const, text: peers.length > 0 ? peers.join("\n") : "(no peers)" }] };
  } catch (e) {
    return { content: [{ type: "text" as const, text: `list_peers failed: ${String(e)}` }], isError: true };
  }
});

mcp.registerTool("agent_send", {
  description: 'Send a message to another agent. Use "broadcast" to send to all peers. `re` (optional) must be an incoming envelope id — a UUID; never an arbitrary token (the wire rejects it).',
  inputSchema: {
    to: z.string().describe('Peer address from list_peers (form "<cwd>@<name>", or "<pc>:<cwd>@<name>" cross-PC) echoed verbatim, or "broadcast"'),
    body: z.unknown().describe("Message body — any JSON value"),
    re: z.string().regex(ENVELOPE_ID_RE,
      "re must be an incoming envelope id (UUID) — put thread/correlation tokens in the body text",
    ).optional().describe("Optional: id of the message you are replying to (UUID only)"),
  },
}, async ({ to, body, re }) => {
  if (!meshReady || mesh === null) return notReady();
  if (to === mesh.address() || to === mesh.name()) {
    return { content: [{ type: "text" as const, text: "Cannot send to yourself" }], isError: true };
  }
  try {
    if (to === "broadcast") {
      await mesh.send(to, body, re ?? null);
      return { content: [{ type: "text" as const, text: "Broadcast sent" }] };
    }
    const ack = await mesh.sendWithAck(to, body, re ?? null);
    const note =
      ack.status === "received" ? `Delivered to ${ack.target ?? to}` :
      // plan/34 removed busy-drop: the current broker NEVER returns `busy`. So
      // if we still see it, the broker LEADER in this mesh is an out-of-date
      // process (e.g. a long-running Pi/agent that leads the local broker and
      // predates the new build) — and that old code DROPPED this message. Be
      // honest: this was NOT delivered. Fix = restart the leader agent.
      ack.status === "busy" ?
        `NOT delivered — "${to}" came back BUSY, which only happens when an ` +
        `OUT-OF-DATE broker leader dropped the message (busy was removed in the ` +
        `current version). Restart the agent that leads the local broker (the ` +
        `oldest Pi/outpost-pi process) so it picks up the new build, then resend.` :
      ack.status === "denied" ? `${to} denied the message` :
      ack.status === "invalid_envelope" ?
        `NOT delivered — the broker rejected the envelope as malformed (e.g. a non-UUID re; ` +
        `a pre-fix broker drops such envelopes silently). Fix the envelope fields and resend.` :
      `No ACK from ${to} (timeout) — peer may be offline`;
    return {
      content: [{ type: "text" as const, text: note }],
      ...(ack.status === "received" ? {} : { isError: true }),
    };
  } catch (e) {
    return { content: [{ type: "text" as const, text: `send failed: ${String(e)}` }], isError: true };
  }
});

mcp.registerTool("get_messages", {
  description: "Return and clear all pending incoming messages from other agents. Call at the start of each turn.",
  inputSchema: {},
}, async () => {
  const { items: msgs, dropped } = inbox.drain();
  // A full drain empties the inbox: re-arm the wake edge and cancel any
  // pending deferred re-check (nothing left to wake about).
  if (msgs.length > 0) wakeCoordinator.onDrain();
  if (msgs.length === 0 && dropped === 0) {
    return { content: [{ type: "text" as const, text: "(no messages)" }] };
  }
  const dropNote = dropped > 0 ? `⚠ ${dropped} earlier message(s) shed by the inbox bound (count/bytes)\n\n` : "";
  const lines = msgs.map((m) => renderInboxMessage(m));
  return { content: [{ type: "text" as const, text: dropNote + lines.join("\n\n") }] };
});

// ── Main ──────────────────────────────────────────────────────────────────────

function isoNow(): string {
  return new Date().toISOString();
}

// Background lock+join state. The cwd lock is (cwd, name)-scoped (plan/41):
// several outpost-pi agents — Pi OR Claude — may share one folder under
// distinct names; a same-named pair would be a ghost (the broker keys
// addresses by (cwd, name)), so the lock refuses the exact name and we
// coexist under a `#N` suffix — the same scheme the broker applies to
// registrations and the Pi extension's `/outpost-pi` applies to its lock.
//
// We retry the REQUESTED name briefly — just enough to ride out a restart
// RACE (the previous endpoint for this name is still tearing down when
// Claude respawns us). After that grace, a live holder means genuine
// cohabitation (e.g. a resident Pi agent under the folder's default name),
// and we take the next free suffixed name instead of failing. Only exhausting
// the whole walk (or repeated join failures) FAILS LOUD (exit non-zero):
// that state is pathological, and Claude surfacing the MCP as errored is the
// desired visibility.
const JOIN_RETRY_MS = 2_000;
const MAX_JOIN_ATTEMPTS = 4;  // ~6–8s grace for a restart race, then coexist/fail loud
let _lock: AcquiredLock | null = null;
let _lockedName: string | null = null;
// Set once the requested name is proven held by a live cohabitant (grace
// exhausted) — later re-walks (e.g. after a failed join released the lock)
// go straight to the suffix walk instead of re-waiting the grace.
let _graceExhausted = false;
let _contentionWarned = false;
let _lockRetryTimer: ReturnType<typeof setTimeout> | null = null;
let _lockAttempt = 0;
let _joined = false;
let _shuttingDown = false;

async function main(): Promise<void> {
  // Subscribe-BEFORE-connect happens inside tryJoinMesh at MeshNode creation
  // (the node is built post-lock-walk so it carries the locked identity).

  // Connect the stdio transport FIRST and unconditionally, so Claude Code
  // always sees this server as connected and the tools stay reachable — even
  // before (or entirely without) a mesh join. The mesh join is layered on
  // best-effort below; a busy folder no longer kills the MCP.
  const transport = new StdioServerTransport();
  transport.onclose = shutdown;
  process.stdin.on("end", shutdown);
  process.stdin.on("close", shutdown);
  await mcp.connect(transport);

  // Only join the mesh if this folder is an actual outpost-pi agent — i.e. it
  // has a local config (written by the `outpost-pi claude` wizard) or an
  // explicit name override. `-s local` MCP registrations are inherited by
  // EVERY claude session in the git repo, so without this gate a plain claude
  // opened in any subfolder would auto-grab that folder's lock and join as a
  // stray agent — colliding with the real agent. No config ⇒ stay connected
  // but idle (tools report why); don't lock, don't join, don't retry.
  if (localConfigExists(_cwd) || _nameOverride !== undefined) {
    // Kick off the lock+join in the background. Never awaited — the MCP is
    // already serving; mesh availability arrives (and recovers) asynchronously.
    void tryJoinMesh();
  } else {
    degradedReason =
      `this folder is not a outpost-pi agent (no config). Run "outpost-pi claude" ` +
      `here to make it one. Mesh tools are idle.`;
  }
}

/** Acquire the (cwd, name)-scoped lock, then join the mesh under the LOCKED
 *  identity. The requested name gets a brief grace to ride out a restart
 *  race; after that a live holder means coexistence and we suffix. Join
 *  failures still retry then fail loud. */
async function tryJoinMesh(): Promise<void> {
  if (_joined || _shuttingDown) return;

  if (_lock === null) {
    const res = await acquireCwdLock(_cwd, AGENT_NAME);
    if (!res.ok) {
      _lockAttempt++;
      if (_lockAttempt < MAX_JOIN_ATTEMPTS && !_graceExhausted) {
        if (!_contentionWarned) {
          _contentionWarned = true;
          warnChannel(
            `outpost-pi-mesh: the mesh name "${AGENT_NAME}" is currently held by a live agent ` +
            `(lock ${res.lockPath}). Retrying briefly in case that is a restart in flight; ` +
            `if it persists, this endpoint will coexist under a #N-suffixed name.`,
          );
        }
        degradedReason =
          `folder busy: mesh name "${AGENT_NAME}" held by a live agent (lock ${res.lockPath}); ` +
          `attempt ${_lockAttempt}/${MAX_JOIN_ATTEMPTS}`;
        _scheduleJoinRetry(JOIN_RETRY_MS);
        return;
      }
      // Grace exhausted → the holder is a live cohabitant, not a restart
      // race. Walk the shared `#N` suffix scheme (same as the broker's
      // registration walk) until a name binds; register under that name.
      const unique = await acquireUniqueNamedCwdLock(_cwd, AGENT_NAME);
      if (unique === null) {
        _failLoud(
          `name space exhausted: every lock from "${AGENT_NAME}" through ` +
          `"${AGENT_NAME}#999" is held (first refusal: ${res.lockPath})`,
        );
      }
      _graceExhausted = true;
      _lock = unique.lock;
      _lockedName = unique.name;
      _lockAttempt = 0;
      warnChannel(
        `outpost-pi-mesh: requested name "${AGENT_NAME}" is taken by a live same-folder agent — ` +
        `coexisting as "${unique.name}". Confirm your exact address via list_peers.`,
      );
    } else {
      _lock = res;
      _lockedName = AGENT_NAME;
      _lockAttempt = 0;
    }
  }

  // Build (or rebuild, if a failed join released the lock and the re-walk
  // landed on a different name) the node under the locked identity, and
  // subscribe BEFORE connecting so we don't miss early envelopes. The
  // SessionPeer swallows broker ACKs / system events itself, so handlers
  // only see real peer messages (and replies, which carry `re`).
  if (mesh === null || _meshName !== _lockedName) {
    const lockedName = _lockedName!;
    mesh = new MeshNode({
      sockPath: BROKER_SOCK,
      name: lockedName, // plan/38: register with (cwd, name) → address `<cwd>@<name>`
      cwd: _canonCwd,
      auditPath: AUDIT_PATH,
      // Own Pi-key cross-PC bridge — active only when this node leads (no Pi /
      // daemon already hosting the broker for this cwd). As a follower the
      // bridge stays dormant and cross-PC rides the existing leader.
      ...(relayBridgeEnabled ? { bridge: { relayUrl: relayResolution.url, cwd: _cwd } } : {}),
      // Silent: stdout is the MCP JSON-RPC channel and stderr noise isn't wanted.
      // Real failures still surface via the global handlers / fail-loud below.
      log: () => { /* no-op */ },
    });
    _meshName = lockedName;
    mesh.onMessage((env) => {
      // plan/34 (passive presence): broker control/system envelopes
      // (`peer_joined` / `peer_left` / `list_peers_reply`) are presence signals,
      // NOT agent messages. Never push them to the inbox or the claude/channel —
      // otherwise a peer joining/leaving would wake this agent's turn. Discovery
      // is pull-based via `list_peers`. (Real broker ACKs and `re` replies are
      // already swallowed upstream by SessionPeer.)
      if (env.from === "broker" || env.from.endsWith(":broker")) return;
      // Shutdown boundary (scan-lifecycle): no wake scheduling once teardown
      // begins — a late mesh message during mesh.close() must not arm a
      // deferred timer that fires into a closing transport.
      if (_shuttingDown) return;

      const msg: IncomingMsg = {
        from: env.from,
        body: env.body,
        id: env.id,
        re: env.re,
        at: isoNow(),
      };
      // Local-only, edge-triggered, rate-capped wake decision (see
      // createWakeCoordinator). Only sessions launched with the dev-channels
      // flag honor the notification — for everyone else it is inertly ignored
      // and get_messages polling remains the delivery path.
      wakeCoordinator.onMessage(msg);
    });
  }

  try {
    await mesh!.connect();
    meshReady = true;
    _joined = true;
    _lockAttempt = 0;
  } catch (e) {
    // Got the lock but the broker join failed (e.g. socket churn). Release the
    // lock so another contender isn't starved, then retry / fail loud.
    _lockAttempt++;
    try { _lock?.release(); } catch { /* best-effort */ }
    _lock = null;
    _lockedName = null;
    if (_lockAttempt >= MAX_JOIN_ATTEMPTS) {
      _failLoud(`mesh join failed: ${String(e)}`);
    }
    degradedReason = `mesh join failed (attempt ${_lockAttempt}/${MAX_JOIN_ATTEMPTS}): ${String(e)}`;
    _scheduleJoinRetry(JOIN_RETRY_MS);
  }
}

function _scheduleJoinRetry(delayMs: number): void {
  if (_lockRetryTimer || _joined || _shuttingDown) return;
  const t = setTimeout(() => {
    _lockRetryTimer = null;
    void tryJoinMesh();
  }, delayMs);
  // Don't let the retry timer alone keep the process alive past stdin close.
  t.unref?.();
  _lockRetryTimer = t;
}

/** Exit non-zero with a loud, specific reason so Claude surfaces the MCP as
 *  errored (visible) instead of a silent connected-but-idle peer. The reason
 *  also goes out on the MCP logging channel — Claude Code does not record an
 *  MCP server's stderr, so stderr alone was invisible to the client. */
function _failLoud(reason: string): never {
  warnChannel(`FATAL: ${reason} — the outpost-pi-mesh MCP will exit so the failure is visible.`);
  logErr(
    `FATAL: ${reason}. Exiting so the failure is visible. cwd=${_cwd}, requested name "${AGENT_NAME}". ` +
    `Either close the duplicate/wedged agents holding this folder's names, or give this ` +
    `endpoint a distinct name ("outpost-pi claude" setup, --name, or OUTPOST_PI_MCP_NAME).`,
  );
  process.exit(1);
}

// Hard-exit bound for the graceful shutdown sequence: a wedged mesh.close()
// (e.g. broker socket stuck half-closed) must not hang this process forever
// holding the (cwd, name) lock — the orphaned-lock hazard. Process exit is
// what actually releases a UDS lock, so force it.
const SHUTDOWN_TIMEOUT_MS = 3_000;

// Exit cleanly when Claude Code disconnects. The MeshNode keeps a UDS socket
// (and, when leader, a relay WS) open, so without this the process would linger
// after Claude exits — orphaning the mesh peer (it keeps showing "online" with
// nothing attached). We leave the mesh, then exit. Triggered by the MCP
// transport closing or stdin hitting EOF (whichever the host does first).
function shutdown(): void {
  if (_shuttingDown) return;
  _shuttingDown = true;
  if (_lockRetryTimer) { clearTimeout(_lockRetryTimer); _lockRetryTimer = null; }
  // Cancel any pending deferred wake synchronously (scan-lifecycle): its
  // callback would otherwise fire a notification during/after teardown —
  // unref() keeps it from holding the process open but never cancels it.
  if (_deferredWakeTimer) { clearTimeout(_deferredWakeTimer); _deferredWakeTimer = null; }
  const hardExit = setTimeout(() => {
    logErr(`shutdown exceeded ${SHUTDOWN_TIMEOUT_MS}ms — hard exit; the OS releases the cwd lock with the process`);
    process.exit(0);
  }, SHUTDOWN_TIMEOUT_MS);
  hardExit.unref?.();
  try { _lock?.release(); } catch { /* OS frees the UDS lock on exit anyway */ }
  void Promise.resolve(mesh === null ? undefined : mesh.close())
    .catch(() => { /* best-effort */ })
    .finally(() => process.exit(0));
}

main().catch((err: unknown) => {
  process.stderr.write(`[outpost-pi-mesh] fatal: ${String(err)}\n`);
  process.exit(1);
});
