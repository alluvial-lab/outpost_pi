import { createHash, createHmac, hkdfSync, randomBytes, timingSafeEqual } from "node:crypto";
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";
import { x25519 } from "@noble/curves/ed25519.js";

/** Domain separator for the paired app↔Pi owner channel. */
export const OWNER_CHANNEL_SUITE = "outpost-pi-owner-channel-v1";

const FRAME_VERSION = 0x01;
const SEQ_BYTES = 8;
const NONCE_BYTES = 24;
const TAG_BYTES = 16;
const FRAME_HEADER_BYTES = 1 + SEQ_BYTES + NONCE_BYTES;
const MAX_UINT64 = (1n << 64n) - 1n;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

/** Hold the independent keys used to send and receive protected owner frames. */
export interface DirectionalKeys {
  send: Uint8Array;
  recv: Uint8Array;
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

function seqLe64(seq: bigint): Uint8Array {
  if (seq < 0n || seq > MAX_UINT64) throw new RangeError("owner channel sequence must fit uint64");
  const output = new Uint8Array(SEQ_BYTES);
  new DataView(output.buffer).setBigUint64(0, seq, true);
  return output;
}

function derive(shared: Uint8Array, tokenBytes: Uint8Array, direction: "app->pi" | "pi->app"): Uint8Array {
  return new Uint8Array(
    hkdfSync("sha256", shared, tokenBytes, utf8(`${OWNER_CHANNEL_SUITE}\n${direction}`), 32),
  );
}

let nonceSource = (): Uint8Array => randomBytes(NONCE_BYTES);

/** Test-only: replace random nonce generation and return a restoration closure. */
export function _setOwnerChannelNonceSourceForTest(source: (() => Uint8Array) | null): () => void {
  const prior = nonceSource;
  nonceSource = source ?? (() => randomBytes(NONCE_BYTES));
  return () => { nonceSource = prior; };
}

/** Generate an independent ephemeral X25519 keypair for one pairing attempt. */
export function generateX25519Keypair(): { pk: Uint8Array; sk: Uint8Array } {
  const { publicKey, secretKey } = x25519.keygen();
  return { pk: publicKey, sk: secretKey };
}

/** Derive an X25519 shared secret, rejecting malformed or low-order public keys. */
export function x25519Shared(sk: Uint8Array, pk: Uint8Array): Uint8Array {
  if (sk.length !== 32 || pk.length !== 32) throw new Error("X25519 keys must be 32 bytes");
  return x25519.getSharedSecret(sk, pk);
}

/** Derive side-relative send and receive keys using the pairing token as HKDF salt. */
export function deriveDirectionalKeys(
  shared: Uint8Array,
  token: string,
  side: "app" | "pi",
): DirectionalKeys {
  if (shared.length !== 32) throw new Error("X25519 shared secret must be 32 bytes");
  const tokenBytes = utf8(token);
  const appToPi = derive(shared, tokenBytes, "app->pi");
  const piToApp = derive(shared, tokenBytes, "pi->app");
  return side === "app"
    ? { send: appToPi, recv: piToApp }
    : { send: piToApp, recv: appToPi };
}

/** Derive the public 16-byte locator for one raw pairing token. */
export function pairTokenId(token: string): Uint8Array {
  return Uint8Array.from(createHash("sha256").update(utf8(token)).digest().subarray(0, 16));
}

/** Build the token-keyed pairing proof transcript from relay-visible fields. */
export function pairMacMessage(
  tokenId: Uint8Array,
  ownerEdPk: Uint8Array,
  appDhPk: Uint8Array,
  piEdPk: Uint8Array,
): Uint8Array {
  if (tokenId.length !== 16) throw new Error("owner channel token id must be 16 bytes");
  if (ownerEdPk.length !== 32 || appDhPk.length !== 32 || piEdPk.length !== 32) {
    throw new Error("owner channel pairing public keys must be 32 bytes");
  }
  return concat(utf8(`${OWNER_CHANNEL_SUITE}\npair\n`), tokenId, ownerEdPk, appDhPk, piEdPk);
}

/** Compute the HMAC proving knowledge of the raw QR token without sending it. */
export function computePairMac(
  token: string,
  tokenId: Uint8Array,
  ownerEdPk: Uint8Array,
  appDhPk: Uint8Array,
  piEdPk: Uint8Array,
): Uint8Array {
  return Uint8Array.from(
    createHmac("sha256", utf8(token))
      .update(pairMacMessage(tokenId, ownerEdPk, appDhPk, piEdPk))
      .digest(),
  );
}

/** Verify a pairing proof in constant time after validating its fixed-width fields. */
export function verifyPairMac(
  token: string,
  tokenId: Uint8Array,
  ownerEdPk: Uint8Array,
  appDhPk: Uint8Array,
  piEdPk: Uint8Array,
  candidate: Uint8Array,
): boolean {
  if (candidate.length !== 32) return false;
  try {
    const expected = computePairMac(token, tokenId, ownerEdPk, appDhPk, piEdPk);
    return timingSafeEqual(expected, candidate);
  } catch {
    return false;
  }
}

/** Build the Owner-signed transcript that binds the app DH share to this Pi identity and QR token. */
export function appTranscript(token: string, appDhPk: Uint8Array, piEdPk: Uint8Array): Uint8Array {
  return concat(utf8(`${OWNER_CHANNEL_SUITE}\napp\n`), utf8(token), appDhPk, piEdPk);
}

/** Build the Pi-signed transcript that binds both DH shares to the authenticated Owner and QR token. */
export function piTranscript(
  token: string,
  appDhPk: Uint8Array,
  piDhPk: Uint8Array,
  ownerEdPk: Uint8Array,
): Uint8Array {
  return concat(utf8(`${OWNER_CHANNEL_SUITE}\npi\n`), utf8(token), appDhPk, piDhPk, ownerEdPk);
}

/** Seal one JSON payload as `version || seqLE64 || nonce24 || ciphertext+tag`. */
export function seal(key: Uint8Array, seq: bigint, json: string): Uint8Array {
  if (key.length !== 32) throw new Error("owner channel key must be 32 bytes");
  const seqBytes = seqLe64(seq);
  const nonce = nonceSource();
  if (nonce.length !== NONCE_BYTES) throw new Error("owner channel nonce must be 24 bytes");
  const ciphertext = xchacha20poly1305(key, nonce, seqBytes).encrypt(utf8(json));
  return concat(Uint8Array.of(FRAME_VERSION), seqBytes, nonce, ciphertext);
}

/**
 * Open one protected owner frame and enforce its persisted replay high-water.
 *
 * Attacker-controlled format, replay, UTF-8, and AEAD failures return `null`;
 * they never escape as exceptions.
 */
export function open(
  key: Uint8Array,
  frame: Uint8Array,
  lastSeq: bigint,
): { seq: bigint; json: string } | null {
  try {
    if (key.length !== 32 || frame.length < FRAME_HEADER_BYTES + TAG_BYTES) return null;
    if (frame[0] !== FRAME_VERSION) return null;

    const seqBytes = frame.subarray(1, 1 + SEQ_BYTES);
    const seq = new DataView(seqBytes.buffer, seqBytes.byteOffset, seqBytes.byteLength).getBigUint64(0, true);
    if (seq <= lastSeq) return null;

    const nonceStart = 1 + SEQ_BYTES;
    const nonce = frame.subarray(nonceStart, nonceStart + NONCE_BYTES);
    const ciphertext = frame.subarray(FRAME_HEADER_BYTES);
    const plaintext = xchacha20poly1305(key, nonce, seqBytes).decrypt(ciphertext);
    return { seq, json: decoder.decode(plaintext) };
  } catch {
    return null;
  }
}
