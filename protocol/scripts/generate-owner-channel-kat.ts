import { hkdfSync } from "node:crypto";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { x25519, ed25519 } from "@noble/curves/ed25519.js";
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";

const SUITE = "outpost-pi-owner-channel-v1";
const encoder = new TextEncoder();
const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const outputPath = join(scriptDirectory, "..", "fixtures", "app-pi", "owner-channel-kat.json");

function bytes(hex: string): Uint8Array {
  if (!/^(?:[0-9a-f]{2})+$/i.test(hex)) throw new Error("expected an even-length hexadecimal byte string");
  return Uint8Array.from(Buffer.from(hex, "hex"));
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const output = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function utf8(value: string): Uint8Array {
  return encoder.encode(value);
}

function base64(value: Uint8Array): string {
  return Buffer.from(value).toString("base64");
}

function hex(value: Uint8Array): string {
  return Buffer.from(value).toString("hex");
}

function seqLe64(seq: bigint): Uint8Array {
  const output = new Uint8Array(8);
  new DataView(output.buffer).setBigUint64(0, seq, true);
  return output;
}

function derive(shared: Uint8Array, tokenBytes: Uint8Array, direction: "app->pi" | "pi->app"): Uint8Array {
  return new Uint8Array(hkdfSync("sha256", shared, tokenBytes, utf8(`${SUITE}\n${direction}`), 32));
}

function seal(key: Uint8Array, nonce: Uint8Array, seq: bigint, plaintextJson: string): Uint8Array {
  const ciphertext = xchacha20poly1305(key, nonce, seqLe64(seq)).encrypt(utf8(plaintextJson));
  return concat(Uint8Array.of(0x01), nonce, ciphertext);
}

const token = "kat-owner-pairing-token-v1";
const tokenBytes = utf8(token);
const appDhSk = bytes("00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f");
const piDhSk = bytes("f0e0d0c0b0a090807060504030201000112233445566778899aabbccddeeff00");
const ownerEdSk = bytes("4f3c2b1a09182736455463728190afbecddcebfa102938475665748392a1b0cf");
const piEdSk = bytes("c0b1a2938475665748392a1bfceddecdbeaf908172635445362718091a2b3c4d");

const appDhPk = x25519.getPublicKey(appDhSk);
const piDhPk = x25519.getPublicKey(piDhSk);
const ownerEdPk = ed25519.getPublicKey(ownerEdSk);
const piEdPk = ed25519.getPublicKey(piEdSk);
const shared = x25519.getSharedSecret(appDhSk, piDhPk);
const peerShared = x25519.getSharedSecret(piDhSk, appDhPk);
if (hex(shared) !== hex(peerShared)) throw new Error("X25519 shared-secret mismatch");

const kAppToPi = derive(shared, tokenBytes, "app->pi");
const kPiToApp = derive(shared, tokenBytes, "pi->app");
const appTranscript = concat(utf8(`${SUITE}\napp\n`), tokenBytes, appDhPk, piEdPk);
const piTranscript = concat(utf8(`${SUITE}\npi\n`), tokenBytes, appDhPk, piDhPk, ownerEdPk);
const appDhSig = ed25519.sign(appTranscript, ownerEdSk);
const piDhSig = ed25519.sign(piTranscript, piEdSk);
if (!ed25519.verify(appDhSig, appTranscript, ownerEdPk)) throw new Error("app signature verification failed");
if (!ed25519.verify(piDhSig, piTranscript, piEdPk)) throw new Error("Pi signature verification failed");

const frames = [
  {
    dir: "app->pi",
    seq: 1,
    nonce: bytes("000102030405060708090a0b0c0d0e0f1011121314151617"),
    plaintextJson: '{"type":"ping","id":"kat-ping-1"}',
    key: kAppToPi,
  },
  {
    dir: "pi->app",
    seq: 1,
    nonce: bytes("18191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f"),
    plaintextJson: '{"type":"pong","in_reply_to":"kat-ping-1"}',
    key: kPiToApp,
  },
  {
    dir: "app->pi",
    seq: 2,
    nonce: bytes("303132333435363738393a3b3c3d3e3f4041424344454647"),
    plaintextJson: '{"type":"ping","id":"kat-ping-2"}',
    key: kAppToPi,
  },
] as const;

const kat = {
  suite: SUITE,
  token,
  app_dh_sk: base64(appDhSk),
  app_dh_pk: base64(appDhPk),
  pi_dh_sk: base64(piDhSk),
  pi_dh_pk: base64(piDhPk),
  owner_ed_sk: base64(ownerEdSk),
  owner_ed_pk: base64(ownerEdPk),
  pi_ed_sk: base64(piEdSk),
  pi_ed_pk: base64(piEdPk),
  shared_secret: base64(shared),
  k_app_to_pi: base64(kAppToPi),
  k_pi_to_app: base64(kPiToApp),
  app_transcript_hex: hex(appTranscript),
  app_dh_sig: base64(appDhSig),
  pi_transcript_hex: hex(piTranscript),
  pi_dh_sig: base64(piDhSig),
  frames: frames.map(({ dir, seq, nonce, plaintextJson, key }) => ({
    dir,
    seq,
    nonce: base64(nonce),
    plaintext_json: plaintextJson,
    sealed_b64: base64(seal(key, nonce, BigInt(seq), plaintextJson)),
  })),
};

writeFileSync(outputPath, `${JSON.stringify(kat, null, 2)}\n`);
