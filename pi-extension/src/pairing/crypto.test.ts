import { describe, expect, it } from "vitest";

import { deviceIdFromPublicKey, generateEd25519Keypair } from "./crypto.js";

describe("deviceIdFromPublicKey", () => {
  it("derives a stable 32-char hex id from a public key", () => {
    const kp = generateEd25519Keypair();
    const id = deviceIdFromPublicKey(kp.publicKey);

    // 128-bit base16 = 32 chars.
    expect(id).toHaveLength(32);
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it("is deterministic — same key → same id", () => {
    const kp = generateEd25519Keypair();
    expect(deviceIdFromPublicKey(kp.publicKey)).toBe(
      deviceIdFromPublicKey(kp.publicKey),
    );
  });

  it("differs across distinct keys", () => {
    const a = generateEd25519Keypair();
    const b = generateEd25519Keypair();
    expect(deviceIdFromPublicKey(a.publicKey)).not.toBe(
      deviceIdFromPublicKey(b.publicKey),
    );
  });
});
