import { createHash, randomBytes } from "node:crypto";
import * as ed from "@noble/ed25519";

// Configure @noble/ed25519 v3 to use Node.js built-in SHA-512
(ed.hashes as Record<string, unknown>)["sha512"] = (
  ...msgs: Uint8Array[]
) => {
  const h = createHash("sha512");
  for (const m of msgs) h.update(m);
  return Uint8Array.from(h.digest());
};

export interface Ed25519Keypair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

/** Generates an Ed25519 keypair for relay challenge-response auth. */
export function generateEd25519Keypair(): Ed25519Keypair {
  const secretKey = randomBytes(32);
  const publicKey = ed.getPublicKey(secretKey);
  return { secretKey, publicKey: Buffer.from(publicKey) };
}

export function ed25519Sign(sk: Uint8Array, msg: Uint8Array): Uint8Array {
  return Buffer.from(ed.sign(msg, sk));
}

export function ed25519Verify(
  pk: Uint8Array,
  msg: Uint8Array,
  sig: Uint8Array,
): boolean {
  return ed.verify(sig, msg, pk);
}

/**
 * Derives a stable per-PC `device_id` from the Pi-key's public key (SHA-256,
 * base16, first 32 chars). Used in the relay `hello` frame so the relay can
 * close prior conn(s) from the same device on duplicate auth (a reconnect)
 * without waiting for ping timeout — see
 * `story-relay-close-same-device-duplicate-auth`.
 *
 * Deterministic derivation (vs. a separate persisted random id) needs no
 * extra storage: the Pi-key is already the per-PC identity, and a reconnect
 * on the same PC presents the same key → same `device_id`. Two PCs with
 * different Pi-keys get different `device_id`s. A copied Pi-key on a second
 * PC (a clone attack, `PROTOCOL.md` Wave E3) would present the same
 * `device_id` and close the prior conn — which is the desired behavior for
 * a clone (only one should be live).
 */
export function deviceIdFromPublicKey(publicKey: Uint8Array): string {
  return createHash("sha256").update(publicKey).digest("hex").slice(0, 32);
}
