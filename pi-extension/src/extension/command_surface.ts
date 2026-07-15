import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { CommandSurfacePort, OutpostPiRuntime } from "./ports.js";

/** Supply side-effecting registration operations for the extension command surface. */
export interface CommandSurfaceDeps {
  readonly registerAgentTools: (pi: ExtensionAPI) => void;
  readonly deployAgentNetworkSkill: () => void;
  readonly refreshPairingsCache: () => void;
  readonly registerCommands: (pi: ExtensionAPI) => void;
  readonly startDaemonMode: () => void;
}

/** Register agent tools, commands, and daemon mode through injected composition-root operations. */
export class CommandSurface implements CommandSurfacePort {
  constructor(private readonly deps: CommandSurfaceDeps) {}

  register(pi: ExtensionAPI, _runtime: OutpostPiRuntime): void {
    this.deps.deployAgentNetworkSkill();
    this.deps.refreshPairingsCache();
    this.deps.registerAgentTools(pi);
    this.deps.registerCommands(pi);
    if (process.env["OUTPOST_PI_DAEMON"] === "1") this.deps.startDaemonMode();
  }
}

/** Create the command-surface port owned by an extension runtime. */
export function createCommandSurface(deps: CommandSurfaceDeps): CommandSurfacePort {
  return new CommandSurface(deps);
}
