import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { CockpitControlType } from "../protocol/generated/protocol.generated.js";

/** Derive the system-status discriminator set from the generated cockpit-control registry. */
export type SystemStatusEventType = Extract<CockpitControlType, `outpost-pi:${string}`>;

/** Carry structured extension status to operator UI consumers without entering model context. */
export interface SystemStatusEvent {
  readonly customType: SystemStatusEventType;
  readonly details?: unknown;
}

/** Accept a possibly stale or incomplete session context while locating the live RPC UI. */
export type SystemStatusEventSourceContext = {
  readonly mode?: ExtensionContext["mode"];
  readonly ui?: Pick<ExtensionContext["ui"], "notify">;
} | null | undefined;

/** Narrow the Pi context to the live RPC notification surface used for structured status events. */
export type SystemStatusEventContext = Pick<ExtensionContext, "mode"> & {
  readonly ui: Pick<ExtensionContext["ui"], "notify">;
};

/**
 * Emit a structured status event through Pi's RPC UI protocol.
 *
 * RPC `ui.notify` writes an `extension_ui_request` for the client without
 * creating a session message. Non-RPC modes retain their existing footer and
 * human notification paths and receive no structured machine event here.
 *
 * @returns true when the event was emitted to an RPC UI
 */
export function emitSystemStatusEvent(
  ctx: SystemStatusEventContext,
  event: SystemStatusEvent,
): boolean {
  if (ctx.mode !== "rpc") return false;
  ctx.ui.notify(JSON.stringify(event), "info");
  return true;
}
