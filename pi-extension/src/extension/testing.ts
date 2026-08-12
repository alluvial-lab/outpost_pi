import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { ClientMessage } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { OwnerMultiplexer } from "./owner_multiplexer.js";

export interface OwnerMultiplexerTestHarness {
  activeOwnerCount(): number;
  hasOwner(peerId: string): boolean;
  disconnectOwner(peerId?: string): void;
  fallbackRoute(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

interface OwnerMultiplexerHarnessDeps {
  owners: Pick<OwnerMultiplexer, "activeCount" | "has" | "disconnectOwner" | "entries">;
  routeFrom(sender: PeerChannel, message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

export function createOwnerMultiplexerTestHarness(
  deps: OwnerMultiplexerHarnessDeps,
): OwnerMultiplexerTestHarness {
  return {
    activeOwnerCount: () => deps.owners.activeCount(),
    hasOwner: (peerId) => deps.owners.has(peerId),
    disconnectOwner: (peerId) => { void deps.owners.disconnectOwner(peerId); },
    fallbackRoute: (message, ctx) => {
      const fallback = deps.owners.entries().at(-1)?.channel;
      if (!fallback) return;
      deps.routeFrom(fallback, message, ctx);
    },
  };
}

export interface OutpostPiTestHarness {
  connect(ctx: unknown): Promise<void>;
  stop(ctx: unknown): Promise<void>;
  state(): "idle" | "started" | "paired";
  /**
   * The room this Pi actually registered with the relay (`_myRoomId`), or `null`
   * while idle (relay not yet started). Single source of truth for the
   * App↔Pi room — derived from the mesh-assigned agent name, which may carry a
   * broker collision suffix (`agent#2`, …) that a cwd/name re-derivation can
   * NOT reconstruct. Test harnesses MUST read this rather than re-deriving the
   * room, or they pair on a room the Pi never announced.
   */
  roomId(): string | null;
  routeClientMessage(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

export function createOutpostPiTestHarness(
  deps: OutpostPiTestHarness,
): OutpostPiTestHarness {
  return deps;
}
