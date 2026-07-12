import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { callSupervisor, supervisorOnline, SupervisorOfflineError } from "../../daemon/client.js";
import type { DaemonInfo } from "../../daemon/control_protocol.js";
import { addDaemon, listDaemons, removeDaemon } from "../../daemon/registry.js";
import { defaultAgentName, loadLocalConfig } from "../../session/local_config.js";

export type UiCtx = Pick<ExtensionContext, "ui">;

function notifyOffline(ctx: UiCtx, err: SupervisorOfflineError): void {
  ctx.ui.notify(`[outpost-pi] ${err.message}`, "warning");
}

function formatDaemonTable(daemons: DaemonInfo[]): string {
  if (daemons.length === 0) return "(no daemons registered)";
  const rows = daemons.map((d) => {
    const uptime = d.uptime_s !== undefined ? `${d.uptime_s}s` : "—";
    const pid = d.pid !== undefined ? String(d.pid) : "—";
    const restarts = d.restart_count ?? 0;
    return `  ${d.id}  ${d.state.padEnd(8)}  pid=${pid}  up=${uptime}  restarts=${restarts}  ${d.name}  ${d.cwd}`;
  });
  return rows.join("\n");
}

/** Thin command-surface adapter for daemon registry and fleet operations. */
export class DaemonCommands {
  /**
   * `/outpost-pi create [<cwd>] [--name <name>]`
   *
   * Promotes a folder to a daemon entry in `~/.pi/remote/daemons.json`. The
   * cwd is normalized by `addDaemon`; daemon runtime ownership remains in the
   * supervisor/registry modules.
   */
  async create(arg: string, ctx: UiCtx): Promise<void> {
    const nameMatch = arg.match(/--name\s+"([^"]+)"|--name\s+(\S+)/);
    const name = nameMatch ? (nameMatch[1] ?? nameMatch[2]) : undefined;
    const cwdRaw = arg.replace(/--name\s+"[^"]+"|--name\s+\S+/, "").trim();
    if (!cwdRaw) {
      ctx.ui.notify(
        "[outpost-pi] Usage: /outpost-pi create <absolute-or-relative-cwd> [--name \"Display name\"]",
        "warning",
      );
      return;
    }

    let result: { id: string; cwd: string; name: string };
    try {
      result = addDaemon(cwdRaw, name);
    } catch (err) {
      ctx.ui.notify(`[outpost-pi] create failed: ${String(err)}`, "error");
      return;
    }

    ctx.ui.notify(
      `[outpost-pi] Daemon registered: id=${result.id} name="${result.name}" cwd=${result.cwd}`,
      "info",
    );

    try {
      await callSupervisor({ op: "start", id: result.id });
      ctx.ui.notify(`[outpost-pi] Daemon started: id=${result.id}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) {
        ctx.ui.notify(
          `[outpost-pi] Registered, but the supervisor is offline — not running yet. ` +
          `Run \`outpost-pi install\` (or start \`pi-supervisord\`); it auto-starts on the next supervisor boot.`,
          "warning",
        );
        return;
      }
      ctx.ui.notify(`[outpost-pi] Registered, but auto-start failed: ${String(err)}`, "error");
    }
  }

  async remove(arg: string, ctx: UiCtx): Promise<void> {
    const id = arg.trim();
    if (!id) {
      ctx.ui.notify(
        "[outpost-pi] Usage: /outpost-pi remove <id>. Run /outpost-pi daemons to see ids.",
        "warning",
      );
      return;
    }

    try {
      const data = await callSupervisor({ op: "unregister", id });
      if (!data.removed) {
        const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
        ctx.ui.notify(`[outpost-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
        return;
      }
      ctx.ui.notify(
        `[outpost-pi] Daemon removed + process stopped: id=${id} cwd=${data.cwd}. ` +
        `Local config at ${data.cwd}/.pi/outpost-pi/config.json was kept.`,
        "info",
      );
      return;
    } catch (err) {
      if (!(err instanceof SupervisorOfflineError)) {
        ctx.ui.notify(`[outpost-pi] remove failed: ${String(err)}`, "error");
        return;
      }
    }

    let result: { removed: boolean; cwd?: string };
    try {
      result = removeDaemon(id);
    } catch (err) {
      ctx.ui.notify(`[outpost-pi] remove failed: ${String(err)}`, "error");
      return;
    }

    if (!result.removed) {
      const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
      ctx.ui.notify(`[outpost-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
      return;
    }

    ctx.ui.notify(
      `[outpost-pi] Daemon removed from registry: id=${id} cwd=${result.cwd}. ` +
      `Supervisor was offline, so any running process was NOT stopped. Local config kept.`,
      "warning",
    );
  }

  async list(ctx: UiCtx): Promise<void> {
    if (!(await supervisorOnline())) {
      const registry = listDaemons();
      if (registry.length === 0) {
        ctx.ui.notify("[outpost-pi] No daemons registered. Run /outpost-pi create <cwd>.", "info");
        return;
      }
      const rows = registry.map((d) => {
        const cfg = loadLocalConfig(d.cwd);
        const name = cfg.agent_name ?? defaultAgentName(d.cwd);
        return `  ${d.id}  ${name}  ${d.cwd}  (supervisor offline)`;
      }).join("\n");
      ctx.ui.notify(`[outpost-pi] Daemons (registry only — run install to bring supervisor up):\n${rows}`, "info");
      return;
    }
    try {
      const data = await callSupervisor({ op: "list" });
      ctx.ui.notify(`[outpost-pi] Daemons:\n${formatDaemonTable(data.daemons)}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] daemons failed: ${String(err)}`, "error");
    }
  }

  async status(ctx: UiCtx): Promise<void> {
    try {
      const data = await callSupervisor({ op: "status" });
      ctx.ui.notify(`[outpost-pi] Fleet status:\n${formatDaemonTable(data.daemons)}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] status failed: ${String(err)}`, "error");
    }
  }

  async start(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "start", id });
        ctx.ui.notify(
          data.started
            ? `[outpost-pi] Started daemon ${id} (${data.state}).`
            : `[outpost-pi] Daemon ${id} already ${data.state}.`,
          "info",
        );
        return;
      }
      const data = await callSupervisor({ op: "start_all" });
      ctx.ui.notify(
        `[outpost-pi] Started ${data.started.length} daemon(s), ` +
        `${data.already_running.length} already running.`,
        "info",
      );
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] start failed: ${String(err)}`, "error");
    }
  }

  async stop(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "stop", id });
        ctx.ui.notify(
          data.stopped
            ? `[outpost-pi] Stopped daemon ${id}.`
            : `[outpost-pi] Daemon ${id} already ${data.state}.`,
          "info",
        );
        return;
      }
      const data = await callSupervisor({ op: "stop_all" });
      ctx.ui.notify(
        `[outpost-pi] Stopped ${data.stopped.length} daemon(s), ` +
        `${data.already_stopped.length} already stopped.`,
        "info",
      );
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] stop failed: ${String(err)}`, "error");
    }
  }

  async restart(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "restart", id });
        ctx.ui.notify(`[outpost-pi] Restarted daemon ${id} (${data.state}).`, "info");
        return;
      }
      const data = await callSupervisor({ op: "restart_all" });
      ctx.ui.notify(`[outpost-pi] Restarted ${data.restarted.length} daemon(s).`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] restart failed: ${String(err)}`, "error");
    }
  }

  async send(arg: string, ctx: UiCtx): Promise<void> {
    const m = arg.match(/^(\S+)\s+(?:"([^"]*)"|(.*))$/);
    if (!m) {
      ctx.ui.notify(
        "[outpost-pi] Usage: /outpost-pi daemon send <id> \"<prompt text>\"",
        "warning",
      );
      return;
    }
    const id = m[1]!;
    const text = (m[2] ?? m[3] ?? "").trim();
    if (!text) {
      ctx.ui.notify("[outpost-pi] daemon send: prompt text is empty.", "warning");
      return;
    }
    try {
      const data = await callSupervisor({ op: "send", id, text });
      if (data.delivered) {
        ctx.ui.notify(`[outpost-pi] Sent to ${id}: ${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`, "info");
      } else {
        ctx.ui.notify(`[outpost-pi] daemon ${id} did not accept the prompt (not running?)`, "warning");
      }
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[outpost-pi] daemon send failed: ${String(err)}`, "error");
    }
  }
}
