import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { ed25519Sign, ed25519Verify } from "../pairing/crypto.js";
import {
  _setOwnerChannelNonceSourceForTest,
  OWNER_CHANNEL_SUITE,
  appTranscript,
  deriveDirectionalKeys,
  open,
  piTranscript,
  seal,
  x25519Shared,
} from "./secure_channel.js";

interface KatFrame {
  dir: "app->pi" | "pi->app";
  seq: number;
  nonce: string;
  plaintext_json: string;
  sealed_b64: string;
}

interface OwnerChannelKat {
  suite: string;
  token: string;
  app_dh_sk: string;
  app_dh_pk: string;
  pi_dh_sk: string;
  pi_dh_pk: string;
  owner_ed_sk: string;
  owner_ed_pk: string;
  pi_ed_sk: string;
  pi_ed_pk: string;
  shared_secret: string;
  k_app_to_pi: string;
  k_pi_to_app: string;
  app_transcript_hex: string;
  app_dh_sig: string;
  pi_transcript_hex: string;
  pi_dh_sig: string;
  frames: KatFrame[];
}

const fixturePath = fileURLToPath(
  new URL("../../../protocol/fixtures/app-pi/owner-channel-kat.json", import.meta.url),
);
const kat = JSON.parse(readFileSync(fixturePath, "utf8")) as OwnerChannelKat;
const b64 = (value: string): Uint8Array => Uint8Array.from(Buffer.from(value, "base64"));
const hex = (value: Uint8Array): string => Buffer.from(value).toString("hex");

describe("owner secure channel", () => {
  test("reproduces the cross-language known-answer vector byte-for-byte", () => {
    expect(OWNER_CHANNEL_SUITE).toBe(kat.suite);
    const appDhPk = b64(kat.app_dh_pk);
    const piDhPk = b64(kat.pi_dh_pk);
    const ownerEdPk = b64(kat.owner_ed_pk);
    const piEdPk = b64(kat.pi_ed_pk);

    const sharedFromApp = x25519Shared(b64(kat.app_dh_sk), piDhPk);
    const sharedFromPi = x25519Shared(b64(kat.pi_dh_sk), appDhPk);
    expect(Buffer.from(sharedFromApp).toString("base64")).toBe(kat.shared_secret);
    expect(sharedFromPi).toEqual(sharedFromApp);

    const appKeys = deriveDirectionalKeys(sharedFromApp, kat.token, "app");
    const piKeys = deriveDirectionalKeys(sharedFromPi, kat.token, "pi");
    expect(Buffer.from(appKeys.send).toString("base64")).toBe(kat.k_app_to_pi);
    expect(Buffer.from(appKeys.recv).toString("base64")).toBe(kat.k_pi_to_app);
    expect(piKeys.send).toEqual(appKeys.recv);
    expect(piKeys.recv).toEqual(appKeys.send);

    const appTx = appTranscript(kat.token, appDhPk, piEdPk);
    const piTx = piTranscript(kat.token, appDhPk, piDhPk, ownerEdPk);
    expect(hex(appTx)).toBe(kat.app_transcript_hex);
    expect(hex(piTx)).toBe(kat.pi_transcript_hex);
    expect(Buffer.from(ed25519Sign(b64(kat.owner_ed_sk), appTx)).toString("base64")).toBe(kat.app_dh_sig);
    expect(Buffer.from(ed25519Sign(b64(kat.pi_ed_sk), piTx)).toString("base64")).toBe(kat.pi_dh_sig);

    const highWater = new Map<KatFrame["dir"], bigint>([["app->pi", 0n], ["pi->app", 0n]]);
    for (const frame of kat.frames) {
      const key = frame.dir === "app->pi" ? appKeys.send : piKeys.send;
      const restore = _setOwnerChannelNonceSourceForTest(() => b64(frame.nonce));
      try {
        const sealed = seal(key, BigInt(frame.seq), frame.plaintext_json);
        expect(Buffer.from(sealed).toString("base64")).toBe(frame.sealed_b64);
        const opened = open(key, sealed, highWater.get(frame.dir)!);
        expect(opened).toEqual({ seq: BigInt(frame.seq), json: frame.plaintext_json });
        highWater.set(frame.dir, BigInt(frame.seq));
      } finally {
        restore();
      }
    }
  });

  test("rejects tampering, replay/equal sequence, and wrong versions without throwing", () => {
    const frame = b64(kat.frames[0]!.sealed_b64);
    const key = b64(kat.k_app_to_pi);
    const tampered = Uint8Array.from(frame);
    tampered[tampered.length - 1] ^= 0x01;
    expect(open(key, tampered, 0n)).toBeNull();
    expect(open(key, frame, 1n)).toBeNull();
    const wrongVersion = Uint8Array.from(frame);
    wrongVersion[0] = 0x02;
    expect(open(key, wrongVersion, 0n)).toBeNull();
    expect(open(key, new Uint8Array(), 0n)).toBeNull();
  });

  test("transcript signatures reject a wrong signer and changed binding fields", () => {
    const appDhPk = b64(kat.app_dh_pk);
    const piEdPk = b64(kat.pi_ed_pk);
    const signature = b64(kat.app_dh_sig);
    const transcript = appTranscript(kat.token, appDhPk, piEdPk);

    expect(ed25519Verify(b64(kat.owner_ed_pk), transcript, signature)).toBe(true);
    expect(ed25519Verify(piEdPk, transcript, signature)).toBe(false);
    expect(ed25519Verify(
      b64(kat.owner_ed_pk),
      appTranscript(`${kat.token}-changed`, appDhPk, piEdPk),
      signature,
    )).toBe(false);
    const changedDh = Uint8Array.from(appDhPk);
    changedDh[0] ^= 1;
    expect(ed25519Verify(
      b64(kat.owner_ed_pk),
      appTranscript(kat.token, changedDh, piEdPk),
      signature,
    )).toBe(false);
  });
});
