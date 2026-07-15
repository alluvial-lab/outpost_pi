import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const CONFIG_DIR = path.join(os.homedir(), ".pi", "remote");
const CONFIG_FILE = path.join(CONFIG_DIR, "config.json");

export type OutpostPiConfig = { relay?: string };

/** Load persisted relay settings, treating missing or invalid local storage as unconfigured. */
export function loadConfig(): OutpostPiConfig {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return {};
    return parsed as OutpostPiConfig;
  } catch {
    return {};
  }
}

/** Merge relay settings into the user config file, creating its parent directory when needed. */
export function saveConfig(patch: Partial<OutpostPiConfig>): void {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
  const current = loadConfig();
  const next = { ...current, ...patch };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(next, null, 2));
}

/** Describe a canonical relay URL and the configuration source that supplied it. */
export type ConfiguredRelayResolution = {
  readonly url: string;
  readonly source: "env" | "config";
};

/** Signal that no environment override or persisted relay URL is available. */
export type UnconfiguredRelayResolution = {
  readonly url: null;
  readonly source: "unconfigured";
};

/** Represent explicit relay availability so callers never open a transport on an implicit fallback. */
export type RelayResolution = ConfiguredRelayResolution | UnconfiguredRelayResolution;

/** Resolves the relay URL in canonical http(s):// form, if one is configured. */
export function resolveRelayUrl(): RelayResolution {
  const env = process.env["OUTPOST_PI_RELAY"];
  if (env && env.length > 0) return { url: toHttpUrl(env), source: "env" };
  const cfg = loadConfig();
  if (cfg.relay && cfg.relay.length > 0) return { url: toHttpUrl(cfg.relay), source: "config" };
  return { url: null, source: "unconfigured" };
}

/**
 * Strict validator for **user-provided** relay URLs (via `/outpost-pi
 * set-relay` or `/outpost-pi relay url`).
 *
 * Only accepts `http://` and `https://`. `ws://`/`wss://` are deliberately
 * **rejected** — the canonical form stored in config is http(s):// and the
 * extension converts to ws(s):// internally when opening the WebSocket.
 * Forcing a single scheme at the user boundary avoids two-form drift.
 */
export function isValidRelayUrl(url: string): boolean {
  if (!url) return false;
  const lower = url.toLowerCase();
  if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false;
  try { new URL(url); return true; } catch { return false; }
}

/**
 * Returns true if the URL uses ws:// or wss:// scheme — for emitting a
 * targeted error message when the user pastes a WebSocket URL by mistake.
 */
export function isWebSocketScheme(url: string): boolean {
  const lower = url.toLowerCase();
  return lower.startsWith("ws://") || lower.startsWith("wss://");
}

/**
 * Converts an http(s):// URL to the corresponding ws(s):// form. Used by
 * the transport layer right before opening the WebSocket — config storage
 * and the mesh HTTP client both stay on http(s)://.
 *
 *   https://host  → wss://host
 *   http://host   → ws://host
 *   ws(s)://host  → pass-through (defensive — env overrides or legacy
 *                   configs may still carry ws(s)://)
 */
export function toWebSocketUrl(url: string): string {
  const lower = url.toLowerCase();
  if (lower.startsWith("https://")) return "wss://" + url.slice("https://".length);
  if (lower.startsWith("http://"))  return "ws://"  + url.slice("http://".length);
  return url;
}

/**
 * Inverse of `toWebSocketUrl`. Used by `resolveRelayUrl` to coerce any
 * ws(s):// values back to canonical http(s):// before returning them to
 * the rest of the codebase.
 */
export function toHttpUrl(url: string): string {
  const lower = url.toLowerCase();
  if (lower.startsWith("wss://")) return "https://" + url.slice("wss://".length);
  if (lower.startsWith("ws://"))  return "http://"  + url.slice("ws://".length);
  return url;
}
