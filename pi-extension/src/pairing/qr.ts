import { randomBytes, timingSafeEqual } from "node:crypto";
import qrTerminal from "qrcode-terminal";
import { pairTokenId } from "../transport/secure_channel.js";

/** Default ephemeral-token lifetime (also the QR rotation period). */
export const TOKEN_TTL_MS = 60_000;
/** Bounds for a caller-supplied pairing TTL (e.g. `/outpost-pi pair --ttl <s>`). */
export const PAIR_TTL_MIN_MS = 10_000;
export const PAIR_TTL_MAX_MS = 600_000;

/** Clamp an arbitrary ttl (ms) into the safe pairing range; NaN → default. */
export function clampPairTtlMs(ttlMs: number): number {
  if (!Number.isFinite(ttlMs)) return TOKEN_TTL_MS;
  return Math.min(PAIR_TTL_MAX_MS, Math.max(PAIR_TTL_MIN_MS, Math.floor(ttlMs)));
}

const PAIR_TOKEN_LOCATOR_BYTES = 16;
const MISSING_PAIR_TOKEN_LOCATOR = new Uint8Array(PAIR_TOKEN_LOCATOR_BYTES);

interface ActiveToken {
  token: string;
  tokenId: Uint8Array;
  expiresAt: number;
  consumed: boolean;
}

/** Encapsulates the single active QR token. One instance per Pi process. */
export class QRSession {
  private active: ActiveToken | null = null;

  /** Generates a fresh 16-byte random token encoded as base64url. */
  generateToken(): string {
    return randomBytes(16).toString("base64url");
  }

  /**
   * Issues a new active token, invalidating any previous one.
   * Returns the token and its expiry timestamp.
   */
  issueToken(ttlMs: number = TOKEN_TTL_MS): { token: string; expiresAt: number } {
    const token = this.generateToken();
    const expiresAt = Date.now() + ttlMs;
    this.active = { token, tokenId: pairTokenId(token), expiresAt, consumed: false };
    return { token, expiresAt };
  }

  /**
   * Resolve the retained token record from its public SHA-256 locator.
   *
   * Expiry and consumption are intentionally checked only by consumeToken,
   * after the caller proves token knowledge. The record remains retained until
   * normal QR rotation, replacement, or clear so proof-holders receive an
   * actionable status without exposing token stage to unknown locators.
   */
  findTokenById(tokenId: Uint8Array): string | null {
    if (tokenId.length !== PAIR_TOKEN_LOCATOR_BYTES) return null;

    // Keep the active and absent-record paths structurally equivalent: both
    // compare exactly one fixed-width locator before the caller verifies a MAC.
    const active = this.active;
    const matches = timingSafeEqual(tokenId, active?.tokenId ?? MISSING_PAIR_TOKEN_LOCATOR);
    return active && matches ? active.token : null;
  }

  /** Validates and atomically consumes a token. */
  consumeToken(
    token: string,
  ): "ok" | "expired" | "consumed" | "unknown" {
    if (!this.active || this.active.token !== token) return "unknown";
    if (this.active.consumed) return "consumed";
    if (Date.now() > this.active.expiresAt) return "expired";
    this.active.consumed = true;
    return "ok";
  }

  clear(): void {
    this.active = null;
  }
}

/** Own the process-wide, single-use QR token state for pairing. */
export const qrSession = new QRSession();

// ── URI + display ─────────────────────────────────────────────────────────────

export const PAIR_LINK_ORIGIN = "https://outpost-pi.kevoun.com";
export const PAIR_LINK_PATH = "/pair";

/** Build the room-targeted, verified pairing App Link consumed by the mobile app. */
export function buildQRUri(
  token: string,
  longtermEdPk: Uint8Array, // Ed25519 key that authenticates the signed-DH handshake establishing the E2E owner channel
  sessionName: string,
  /**
   * Pi room id (12 chars, base64url) derived from cwd. App routes pair_request
   * to this room so the relay delivers it to the right Pi instance among N
   * parallel instances with the same epk. Added in the plan 17 fix (without
   * `rm`, the app falls back to room=main and the relay drops it with
   * "dest not found").
   */
  roomId?: string,
): string {
  // `r` (relay URL) removed in plan 14 — relay now comes from app config /
  // pi-ext env|config|default chain. Keeps QR ~30-50 chars shorter.
  // `n` (session name) is kept: the app uses it for the pre-pair_ok preview
  // screen (showing the agent name immediately after scan, before the
  // handshake completes). Dropping it briefly shrank the QR but the QR
  // size no longer matters now that the copy-paste URI is rendered via
  // `pi.sendMessage` into the chat panel (not the QR overflow area).
  const epkB64 = Buffer.from(longtermEdPk).toString("base64url");
  const params = new URLSearchParams({
    t: token,
    epk: epkB64,
    n: sessionName.slice(0, 80),
  });
  if (roomId) params.set("rm", roomId);
  // Keep the enrollment capability in the fragment. Android receives it when
  // dispatching the verified App Link, while an HTTP fallback never sends it
  // to the site or its access logs.
  return `${PAIR_LINK_ORIGIN}${PAIR_LINK_PATH}#${params.toString()}`;
}

/**
 * Returns the QR ASCII as a string (pure Unicode block characters —
 * `█ ▀ ▄` and space, NO ANSI escapes — qrcode-terminal v0.12 small mode
 * is escape-free, see lib/main.js:48-53).
 *
 * The caller can either write the string to stderr (legacy path, breaks
 * the Pi TUI layout) or inject it via `pi.sendMessage` (renders inside
 * the chat panel as proper content).
 */
export function renderQRAscii(uri: string): string {
  let out = "";
  qrTerminal.generate(uri, { small: true }, (qrcode) => { out = qrcode; });
  return out;
}

