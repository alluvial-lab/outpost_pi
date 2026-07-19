import {
  decodeRelayIngress,
  type DecodedRelayIngress,
} from "../protocol/relay_ingress.js";

/** Minimal relay event surface needed by the shared typed ingress fanout. */
export interface RelayIngressMessageSource {
  on(event: "message", handler: (line: string) => void): unknown;
  off(event: "message", handler: (line: string) => void): unknown;
}

type RelayIngressHandler = (ingress: DecodedRelayIngress) => void;

type RelayIngressHub = {
  readonly handlers: Set<RelayIngressHandler>;
  ownerClaimed: boolean;
  fallbackListener: ((line: string) => void) | null;
};

const hubs = new WeakMap<RelayIngressMessageSource, RelayIngressHub>();

function hubFor(source: RelayIngressMessageSource): RelayIngressHub {
  let hub = hubs.get(source);
  if (!hub) {
    hub = { handlers: new Set(), ownerClaimed: false, fallbackListener: null };
    hubs.set(source, hub);
  }
  return hub;
}

function publish(hub: RelayIngressHub, ingress: DecodedRelayIngress): void {
  for (const handler of hub.handlers) handler(ingress);
}

function attachFallback(source: RelayIngressMessageSource, hub: RelayIngressHub): void {
  if (hub.ownerClaimed || hub.fallbackListener || hub.handlers.size === 0) return;
  hub.fallbackListener = (line) => {
    try {
      publish(hub, decodeRelayIngress(line));
    } catch {
      // Invalid wire input is rejected at the shared transport boundary.
    }
  };
  source.on("message", hub.fallbackListener);
}

function detachFallback(source: RelayIngressMessageSource, hub: RelayIngressHub): void {
  if (!hub.fallbackListener) return;
  source.off("message", hub.fallbackListener);
  hub.fallbackListener = null;
}

/**
 * Claim decode ownership for a relay transport and disable the standalone fallback decoder.
 *
 * The returned release closure is idempotent. Existing typed subscribers stay
 * attached but do not resume raw decoding on a stale, released connection.
 */
export function claimRelayIngressFanout(source: RelayIngressMessageSource): () => void {
  const hub = hubFor(source);
  hub.ownerClaimed = true;
  detachFallback(source, hub);
  let released = false;
  return () => {
    if (released) return;
    released = true;
    hub.ownerClaimed = false;
  };
}

/** Publish the transport owner's already-decoded ingress object to every typed listener. */
export function publishRelayIngress(
  source: RelayIngressMessageSource,
  ingress: DecodedRelayIngress,
): void {
  publish(hubFor(source), ingress);
}

/**
 * Subscribe to typed relay ingress with explicit teardown.
 *
 * RelayTransport-owned connections publish their single decoded object here.
 * A directly-owned RelayClient (the standalone mesh path) installs one shared
 * fallback decoder regardless of subscriber count.
 */
export function subscribeRelayIngress(
  source: RelayIngressMessageSource,
  handler: RelayIngressHandler,
): () => void {
  const hub = hubFor(source);
  hub.handlers.add(handler);
  attachFallback(source, hub);
  return () => {
    hub.handlers.delete(handler);
    if (hub.handlers.size === 0) detachFallback(source, hub);
  };
}
