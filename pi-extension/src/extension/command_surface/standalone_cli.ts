import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  isValidRelayUrl,
  isWebSocketScheme,
} from "../../config.js";
import {
  defaultAgentName,
  localConfigExists,
  saveLocalConfig,
} from "../../session/local_config.js";
import type { CronCommands } from "./cron_commands.js";
import type { DaemonCommands, UiCtx } from "./daemon_commands.js";
import type { ServiceCommands } from "./service_commands.js";

/** Provide the command operations exposed by the process-level Outpost-Pi CLI. */
export interface StandaloneCliDeps {
  readonly devices: () => Promise<void>;
  readonly revoke: (shortid: string) => Promise<void>;
  readonly setRelay: (url: string) => void;
  readonly daemon: DaemonCommands;
  readonly cron: CronCommands;
  readonly service: ServiceCommands;
  readonly probePeers: () => Promise<void>;
  readonly launchClaude: (args: string[]) => Promise<void>;
  readonly restartSupervisor: () => void;
}

interface StoredPeer {
  readonly name: string;
  readonly remote_epk: string;
}

/** Supply infrastructure adapters used to assemble a standalone CLI dependency set. */
export interface StandaloneCliAdapterDeps {
  readonly listPeers: () => Promise<StoredPeer[]>;
  readonly removePeer: (remoteEpk: string) => Promise<boolean>;
  readonly saveRelayConfig: (url: string) => void;
  readonly daemon: DaemonCommands;
  readonly cron: CronCommands;
  readonly service: ServiceCommands;
  readonly probeListPeers: () => Promise<string[] | null>;
  readonly formatPeerInventory: (peers: readonly string[]) => string;
  readonly launchClaude: (args: string[]) => Promise<void>;
  readonly restartSupervisor: () => void;
}

/** Assemble standalone CLI operations from injected storage, mesh, and service adapters. */
export function createStandaloneCliDeps(input: StandaloneCliAdapterDeps): StandaloneCliDeps {
  return {
    devices: async () => {
      const peers = await input.listPeers();
      if (peers.length === 0) { console.log("[outpost-pi] No peers"); }
      else { for (const p of peers) console.log(`• ${p.remote_epk.slice(0, 8)} — ${p.name}`); }
    },
    revoke: async (shortid) => {
      const peers = await input.listPeers();
      const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));
      if (matches.length === 0) console.log(`No peer matching '${shortid}'`);
      else if (matches.length > 1) console.log(`Ambiguous: ${matches.map((p) => p.remote_epk.slice(0, 8)).join(", ")}`);
      else {
        const peer = matches[0]!;
        await input.removePeer(peer.remote_epk);
        console.log(`Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`);
      }
    },
    setRelay: input.saveRelayConfig,
    daemon: input.daemon,
    cron: input.cron,
    service: input.service,
    probePeers: async () => {
      const peers = await input.probeListPeers();
      if (peers === null) {
        console.log("[outpost-pi] Mesh offline — no agent is running on this machine.");
      } else {
        console.log(`[outpost-pi] peers:\n${input.formatPeerInventory(peers)}`);
      }
    },
    launchClaude: input.launchClaude,
    restartSupervisor: input.restartSupervisor,
  };
}

export function isDirectRun(importMetaUrl: string, argv1: string | undefined): boolean {
  try {
    if (!argv1) return false;
    return fileURLToPath(importMetaUrl) === realpathSync(argv1);
  } catch {
    return false;
  }
}

/** Dispatch one standalone CLI invocation through injected command operations. */
export async function runStandaloneOutpostPiCli(
  argv: readonly string[],
  deps: StandaloneCliDeps,
): Promise<void> {
  const [, , subcmd, ...cliArgs] = argv;
  if (subcmd === "devices" || subcmd === "list") {
    await deps.devices();
  } else if (subcmd === "revoke") {
    const shortid = (cliArgs[0] ?? "").trim();
    if (!shortid) {
      console.log("Usage: revoke <shortid>");
    } else {
      await deps.revoke(shortid);
    }
  } else if (subcmd === "set-relay") {
    const raw = (cliArgs[0] ?? "").trim();
    if (!raw) {
      console.log("Usage: set-relay <url>");
    } else if (isWebSocketScheme(raw)) {
      console.log("Use http:// or https://. The extension converts to WebSocket automatically.");
    } else if (!isValidRelayUrl(raw)) {
      console.log(`Invalid URL: ${raw}. Must start with http:// or https://`);
    } else {
      deps.setRelay(raw);
      console.log(`Relay set to ${raw}`);
    }
  } else if (subcmd === "create") {
    const joined = quoteArgsWithSpaces(cliArgs);
    await deps.daemon.create(joined, consoleUiCtx());
  } else if (subcmd === "remove") {
    const id = (cliArgs[0] ?? "").trim();
    await deps.daemon.remove(id, consoleUiCtx());
  } else if (subcmd === "daemons") {
    await deps.daemon.list(consoleUiCtx());
  } else if (subcmd === "daemon") {
    const op = cliArgs[0] ?? "";
    const rest = quoteArgsWithSpaces(cliArgs.slice(1));
    const stubCtx = consoleUiCtx();
    if (op === "start") { await deps.daemon.start(stubCtx, cliArgs[1]); }
    else if (op === "stop") { await deps.daemon.stop(stubCtx, cliArgs[1]); }
    else if (op === "restart") { await deps.daemon.restart(stubCtx, cliArgs[1]); }
    else if (op === "status") { await deps.daemon.status(stubCtx); }
    else if (op === "send") { await deps.daemon.send(rest, stubCtx); }
    else {
      console.log("Usage: outpost-pi daemon <start|stop|restart [<id>]|status|send <id> \"<text>\">");
    }
  } else if (subcmd === "cron") {
    const joined = quoteArgsWithSpaces(cliArgs);
    await deps.cron.run(joined, consoleUiCtx());
  } else if (subcmd === "peers") {
    await deps.probePeers();
  } else if (subcmd === "claude") {
    await deps.launchClaude([...cliArgs]);
  } else if (subcmd === "install") {
    if (!deps.service.install(consoleUiCtx(), { linkCli: false })) process.exit(1);
  } else if (subcmd === "uninstall") {
    deps.service.uninstall(consoleUiCtx(), { linkCli: true });
  } else if (subcmd === "restart-supervisor") {
    deps.restartSupervisor();
  } else {
    console.log(outpostPiCliHelpText());
  }
}

function quoteArgsWithSpaces(args: readonly string[]): string {
  return args.map((arg) => (/\s/.test(arg) ? `"${arg}"` : arg)).join(" ");
}

function consoleUiCtx(): UiCtx {
  return {
    ui: {
      notify: (msg: string) => { console.log(msg); },
    } as unknown as ExtensionContext["ui"],
  };
}

function outpostPiCliHelpText(): string {
  return [
    "Usage: outpost-pi <command>",
    "",
    "Daemon registry:",
    "  create <cwd> [--name \"Name\"]   Register a folder as a daemon",
    "  remove <id>                     Unregister a daemon",
    "  daemons                         List registered daemons",
    "",
    "Fleet control:",
    "  daemon start [<id>]             Start all daemons, or one by id",
    "  daemon stop [<id>]              Stop all daemons, or one by id",
    "  daemon restart [<id>]           Restart all daemons, or one by id",
    "  daemon status                   Show pid / uptime / restarts",
    "  daemon send <id> \"<text>\"       Send a prompt to a daemon",
    "  cron add <id> \"<expr>\" \"<txt>\"  Schedule a recurring prompt (≥60s; --tz, --wake)",
    "  cron list|run|remove|log        Manage scheduled prompts (needs the supervisor)",
    "",
    "Service:",
    "  install                         Install pi-supervisord as a system service",
    "  uninstall                       Remove the system service",
    "  restart-supervisor              Restart the pi-supervisord process",
    "",
    "Devices:",
    "  devices                         List paired phones (peers.json)",
    "  revoke <shortid>                Revoke a paired device",
    "",
    "Config:",
    "  set-relay <url>                 Set the relay URL (http:// or https://)",
    "",
    "Agent mesh:",
    "  peers                           List agents on the local + cross-PC mesh",
    "  claude [cwd] [claude-flags]     Start Claude Code on the agent mesh",
    "                                  (safe defaults: Claude permissions stay on,",
    "                                  messages poll at each turn via get_messages;",
    "                                  pass claude flags through to opt in to more;",
    "                                  add --outpost-mesh-wake to let mesh peers",
    "                                  start turns on the idle session)",
  ].join("\n");
}

/** Wrapper-owned opt-in that lets mesh peers start turns on the launched
 *  Claude session (an authority class of its own — "initiative"). Filtered
 *  out of the verbatim passthrough before cwd detection and expanded by
 *  buildClaudeLaunchArgs into the dev-channels flag plus the drain
 *  pre-approval. */
export const MESH_WAKE_FLAG = "--outpost-mesh-wake" as const;

/** Split `outpost-pi claude` argv into the optional leading cwd, the
 *  wrapper-owned wake opt-in, and the verbatim claude-flag passthrough.
 *
 * Contract: `outpost-pi claude [cwd] [--outpost-mesh-wake] [claude-flags...]`.
 * MESH_WAKE_FLAG is filtered out FIRST so it can never shadow the cwd:
 * `outpost-pi claude --outpost-mesh-wake ~/code/api` must resolve the cwd to
 * ~/code/api, not fall back to the invoking cwd and pass ~/code/api through
 * as a prompt positional. The remaining optional cwd is ONLY the leading
 * non-flag token; everything after it is forwarded verbatim to the `claude`
 * binary (e.g. `--resume`, `-c`, `-p "prompt"`) — restricting cwd to the
 * leading token avoids mistaking a flag's value (e.g. the id in
 * `--resume <id>`) for the cwd. With no leading positional, the cwd defaults
 * to the invoking process cwd.
 */
export function splitClaudeCliArgs(
  args: readonly string[],
): { targetCwd: string; meshWake: boolean; passthroughArgs: string[] } {
  const meshWake = args.includes(MESH_WAKE_FLAG);
  const rest = args.filter((arg) => arg !== MESH_WAKE_FLAG);
  const hasCwdArg = rest.length > 0 && !rest[0]!.startsWith("-");
  return {
    targetCwd: hasCwdArg ? rest[0]! : process.cwd(),
    meshWake,
    passthroughArgs: hasCwdArg ? rest.slice(1) : [...rest],
  };
}

/** Build the claude launch flags the wrapper owns: the ephemeral mesh MCP
 *  config plus (when packaged) the agent-network skill append, and — only
 *  behind the explicit MESH_WAKE_FLAG opt-in — the wake expansion.
 *
 * Two guards, deliberately distinct:
 *
 * 1. Authority (absolute): the wrapper NEVER injects
 *    `--dangerously-skip-permissions`. Auto-approving every tool call is the
 *    operator's verbatim-passthrough opt-in alone.
 * 2. Initiative (opt-in): `--dangerously-load-development-channels` lets
 *    mesh peers START turns on the session — it changes no permission
 *    policy, but it widens who can act. The wrapper adds it only when the
 *    operator passed MESH_WAKE_FLAG. The expansion also pre-approves the
 *    read-only `get_messages` drain (`--allowedTools`), so an unattended
 *    woken session can read the message instead of stalling on an approval
 *    dialog nobody will answer.
 *
 * An operator-provided dev-channels flag in the passthrough (either argv
 * form) is respected as-is — no duplicate or clobbering expansion.
 */
export function buildClaudeLaunchArgs(
  mcpConfigPath: string,
  skillPath: string | null,
  meshWake = false,
  passthroughArgs: readonly string[] = [],
): string[] {
  const operatorPassedDevChannels = passthroughArgs.some(
    (arg) => arg === "--dangerously-load-development-channels" || arg.startsWith("--dangerously-load-development-channels="),
  );
  return [
    "--mcp-config", mcpConfigPath,
    ...(skillPath ? [`--append-system-prompt-file=${skillPath}`] : []),
    // The drain pre-approval is independent of the channel dedupe: an
    // operator who passed their own dev-channels flag still asked for wake
    // when they added MESH_WAKE_FLAG — dropping the pre-approval too would
    // stall approval-gated sessions on the very drain the wake requests.
    ...(meshWake && !operatorPassedDevChannels ? [
      "--dangerously-load-development-channels=server:outpost-pi-mesh",
    ] : []),
    ...(meshWake ? [
      "--allowedTools=mcp__outpost-pi-mesh__get_messages",
    ] : []),
  ];
}

/** Write the ephemeral mesh MCP config into a fresh owner-only temp dir.
 *
 * Security contract (gate-security-mcp-tmp-config-path): the config is
 * execution-bearing (Claude launches the server it names), so it must never
 * live at a predictable shared-tmp path — a pre-positioned symlink or a
 * substituted file there would let another local user steer the launch.
 * `mkdtempSync` yields an unpredictable 0700 directory; the file is created
 * exclusively (`wx`) inside it. Returns the config path; the caller removes
 * the whole directory on exit via `removeEphemeralMcpDir`. */
export function writeEphemeralMcpConfig(meshServerPath: string): string {
  const dir = mkdtempSync(join(tmpdir(), "outpost-pi-mesh-mcp-"));
  const configPath = join(dir, "mcp-config.json");
  writeFileSync(configPath, JSON.stringify({
    mcpServers: {
      "outpost-pi-mesh": { command: process.execPath, args: [meshServerPath] },
    },
  }), { flag: "wx" });
  return configPath;
}

/** Remove the ephemeral config directory created by writeEphemeralMcpConfig. */
export function removeEphemeralMcpDir(configPath: string): void {
  rmSync(dirname(configPath), { recursive: true, force: true });
}

/** Launch Claude with an ephemeral Outpost-Pi mesh MCP configuration, terminating on missing build output. */
export async function launchClaudeCli(args: string[], entrypointUrl: string): Promise<void> {
  const { targetCwd, meshWake, passthroughArgs } = splitClaudeCliArgs(args);

  // Wizard when no local config exists
  if (!localConfigExists(targetCwd)) {
    // Fail fast when the wizard cannot run: with non-interactive stdin (e.g.
    // `outpost-pi claude -p …` headless) the readline question never settles and
    // Node exits 13 on the unsettled top-level await. Give the operator the
    // two real options instead of a hang: run interactively once, or pre-create
    // the config (the documented scripted-install path).
    if (!process.stdin.isTTY) {
      console.log(
        `[outpost-pi] No config found for ${targetCwd} and stdin is not a TTY — ` +
        `cannot run the setup wizard headlessly. Run "outpost-pi claude" ` +
        `interactively once, or create ${join(targetCwd, ".pi", "outpost-pi", "config.json")} ` +
        `with { "agent_name": "…", "auto_start_relay": true } first.`,
      );
      process.exit(1);
    }
    const suggested = defaultAgentName(targetCwd);
    process.stdout.write(`\n[outpost-pi] No config found for ${targetCwd}\n`);
    process.stdout.write("Let's set up this agent.\n\n");

    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const agentName: string = await new Promise((res) =>
      rl.question(`Agent name [${suggested}]: `, (ans) => { rl.close(); res(ans.trim() || suggested); }),
    );

    saveLocalConfig(targetCwd, { agent_name: agentName, auto_start_relay: true });
    process.stdout.write(`[outpost-pi] Config saved: agent="${agentName}"\n\n`);
  }

  // Resolve mesh server script path (dist/mcp/mesh_server.js)
  const here = fileURLToPath(entrypointUrl);
  const distRoot = dirname(here);
  const meshServerPath = resolve(distRoot, "mcp/mesh_server.js");

  if (!existsSync(meshServerPath)) {
    console.log(`[outpost-pi] mesh server not found at ${meshServerPath}. Run pnpm build first.`);
    process.exit(1);
  }

  const absCwd = resolve(targetCwd);
  const SERVER_NAME = "outpost-pi-mesh";

  // The mesh MCP must be visible ONLY inside a `outpost-pi claude` session — a
  // plain `claude` in the same repo must NOT inherit it. Remove the legacy
  // local-scope entry left by older builds, then load the server ephemerally
  // through --mcp-config for this launched Claude process only.
  spawnSync("claude", ["mcp", "remove", SERVER_NAME, "-s", "local"], {
    cwd: absCwd, stdio: "ignore", shell: false,
  });

  const mcpConfigPath = writeEphemeralMcpConfig(meshServerPath);

  const skillPath = agentNetworkSkillPath(entrypointUrl);

  try {
    spawnSync("claude", [
      ...buildClaudeLaunchArgs(mcpConfigPath, skillPath, meshWake, passthroughArgs),
      ...passthroughArgs,
    ], {
      cwd: absCwd,
      stdio: "inherit",
      shell: false,
    });
  } finally {
    try { removeEphemeralMcpDir(mcpConfigPath); } catch { /* already removed */ }
  }
}

/**
 * Resolve the packaged agent-network skill path (`<pkgRoot>/skills/agent-network/SKILL.md`).
 * Uses the package entrypoint URL instead of this module URL so the path remains
 * identical after the dispatcher moves under `dist/extension/command_surface/`.
 */
function agentNetworkSkillPath(entrypointUrl: string): string | null {
  const here = fileURLToPath(entrypointUrl);
  const pkgRoot = dirname(dirname(here));
  const skill = join(pkgRoot, "skills", "agent-network", "SKILL.md");
  return existsSync(skill) ? skill : null;
}
