import { mkdir, readFile, writeFile, chmod, unlink, rename } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { AsyncEntry } from "@napi-rs/keyring";
import { generateEd25519Keypair, type Ed25519Keypair } from "./crypto.js";

/**
 * Pi-secret storage (plan/27 Wave E1).
 *
 * The Ed25519 long-term identity of this Pi lives in the platform keyring
 * via `@napi-rs/keyring` (Keychain on macOS, libsecret on Linux desktop,
 * Credential Manager on Windows — DPAPI-backed). When the keyring is
 * unavailable (headless Linux without a D-Bus session, Docker containers,
 * VPS without GNOME Keyring/KWallet running) we fall back to a
 * file-backed store at `~/.pi/remote/identity.json` with `0o600`
 * permissions and the parent dir at `0o700`.
 */

const NEW_SERVICE = "dev.outpostpi.pi";  // platform-neutral
const ACCOUNT = "longterm-ed25519";

/**
 * The keyring read can THROW transiently rather than permanently — most
 * notably a macOS Keychain that's still locked right after login/wake (the
 * machine sat idle for days). Treating that throw as "backend unavailable"
 * and minting a fresh identity silently orphans the paired key (the
 * "lost pairing after a week idle" failure). So we retry the read a few times
 * before ever concluding the keyring is truly unavailable. Overridable for
 * tests via `_setKeyringRetryForTest`. */
let _keyringReadAttempts = 3;
let _keyringRetryDelayMs = 300;

/** Raised when the keyring is unreadable on a platform where it's a core OS
 *  service (macOS Keychain, Windows Credential Manager) AND no prior file
 *  identity exists. We refuse to generate a NEW identity here because that
 *  would break existing pairing — the caller surfaces this so the user can
 *  unlock the keychain and retry instead of silently re-pairing. */
export class KeyringUnavailableError extends Error {
  constructor(cause: unknown) {
    super(
      "Platform keyring is unreadable and no file-backed identity exists. " +
      "Refusing to generate a NEW identity (that would break existing " +
      "pairing). Unlock your keychain / start your secret service and retry. " +
      "Set OUTPOST_PI_ALLOW_FILE_IDENTITY=1 to force a file-backed identity. " +
      `Cause: ${String(cause)}`,
    );
    this.name = "KeyringUnavailableError";
  }
}

const PI_DIR = join(homedir(), ".pi", "remote");
const IDENTITY_FILE = join(PI_DIR, "identity.json");
const PEERS_PATH = join(PI_DIR, "peers.json");

// ── KeyStore abstraction ─────────────────────────────────────────────────────

/**
 * Minimal backend interface for credential reads/writes. Swappable so
 * tests can inject a controlled in-memory store without touching the OS
 * keyring (which is shared with the developer's own credentials).
 *
 * Errors thrown by `read`/`write`/`delete` signal "backend unavailable on
 * this platform" — callers fall back to the file store on first failure.
 * Returning `undefined` from `read` means "no such entry" (a normal,
 * non-error condition).
 */
export interface KeyStoreBackend {
  read(service: string, account: string): Promise<string | undefined>;
  write(service: string, account: string, value: string): Promise<void>;
  delete(service: string, account: string): Promise<boolean>;
}

class NapiKeyringBackend implements KeyStoreBackend {
  async read(service: string, account: string): Promise<string | undefined> {
    const entry = new AsyncEntry(service, account);
    return entry.getPassword();  // returns undefined on no-entry
  }
  async write(service: string, account: string, value: string): Promise<void> {
    const entry = new AsyncEntry(service, account);
    await entry.setPassword(value);
  }
  async delete(service: string, account: string): Promise<boolean> {
    const entry = new AsyncEntry(service, account);
    try {
      return await entry.deleteCredential();
    } catch {
      return false;
    }
  }
}

let _backend: KeyStoreBackend | null = null;

function _getBackend(): KeyStoreBackend {
  if (!_backend) _backend = new NapiKeyringBackend();
  return _backend;
}

/** Test-only: swap (or clear with `null`) the keyring backend. */
export function _setKeyStoreBackendForTest(backend: KeyStoreBackend | null): void {
  _backend = backend;
}

/**
 * Is the platform keyring a CORE OS service we should expect to be present?
 * macOS (Keychain) and Windows (Credential Manager) always have one, so a read
 * that throws there is transient/locked, NOT "headless" — we must not mint a
 * new identity. On Linux/other the secret service may be genuinely absent
 * (headless, no D-Bus), so the documented file fallback applies. Overridable
 * for tests via `_setKeyringExpectedForTest`. */
let _keyringExpectedOverride: boolean | null = null;
function _keyringExpectedAvailable(): boolean {
  if (_keyringExpectedOverride !== null) return _keyringExpectedOverride;
  return process.platform === "darwin" || process.platform === "win32";
}

/** Test-only: force `_keyringExpectedAvailable()` (so a darwin test host can
 *  exercise the Linux/headless branch and vice-versa). `null` restores the
 *  real platform check. */
export function _setKeyringExpectedForTest(value: boolean | null): void {
  _keyringExpectedOverride = value;
}

/** Test-only: shrink retry attempts/delay so the persistent-failure path is
 *  fast. `null`/omitted restores defaults. */
export function _setKeyringRetryForTest(attempts: number | null, delayMs?: number): void {
  _keyringReadAttempts = attempts ?? 3;
  _keyringRetryDelayMs = delayMs ?? 300;
}

function _sleep(ms: number): Promise<void> {
  return ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve();
}

// ── Keypair serialization ────────────────────────────────────────────────────

interface SerializedKeypair {
  pk: string;
  sk: string;
}

function _serialize(kp: Ed25519Keypair): string {
  const payload: SerializedKeypair = {
    pk: Buffer.from(kp.publicKey).toString("base64"),
    sk: Buffer.from(kp.secretKey).toString("base64"),
  };
  return JSON.stringify(payload);
}

function _deserialize(stored: string): Ed25519Keypair {
  const parsed = JSON.parse(stored) as SerializedKeypair;
  return {
    publicKey: Buffer.from(parsed.pk, "base64"),
    secretKey: Buffer.from(parsed.sk, "base64"),
  };
}

// ── File fallback (headless Linux) ──────────────────────────────────────────

async function _readKeypairFromFile(): Promise<Ed25519Keypair | null> {
  try {
    const raw = await readFile(IDENTITY_FILE, "utf8");
    return _deserialize(raw);
  } catch {
    return null;
  }
}

async function _ensurePrivateStorageDir(dir: string): Promise<void> {
  await mkdir(dir, { recursive: true, mode: 0o700 });
  // Best-effort tighten of the dir in case it pre-existed with looser
  // permissions (mkdir's mode is only applied to NEW dirs).
  try { await chmod(dir, 0o700); } catch { /* not fatal */ }
}

async function _writeKeypairToFile(kp: Ed25519Keypair): Promise<void> {
  await _ensurePrivateStorageDir(PI_DIR);
  await writeFile(IDENTITY_FILE, _serialize(kp), { mode: 0o600 });
  try { await chmod(IDENTITY_FILE, 0o600); } catch { /* not fatal */ }
}

// ── Public API ──────────────────────────────────────────────────────────────

/**
 * Returns the Pi-secret Ed25519 keypair, generating + persisting one on
 * first call. Resolution order:
 *   1. Keyring service `dev.outpostpi.pi` (read retried — a transiently
 *      locked Keychain throws; we don't treat that as "no key")
 *   2. File `~/.pi/remote/identity.json` (use if present — never regenerate
 *      over an existing one)
 *   3. Generate a fresh keypair, BUT only when it's safe to: the keyring read
 *      succeeded and returned nothing (genuine first run), or the keyring is
 *      genuinely unavailable on a platform without a core one (headless
 *      Linux). On macOS/Windows a persistent read failure with no file identity
 *      throws `KeyringUnavailableError` instead of minting a new key —
 *      generating there silently breaks existing pairing (the "lost pairing
 *      after idle" bug). `OUTPOST_PI_ALLOW_FILE_IDENTITY=1` opts back into a
 *      file identity for headless macOS/Windows hosts.
 *
 * Idempotent: subsequent calls return the same identity.
 */
export async function getOrCreateEd25519Keypair(): Promise<Ed25519Keypair> {
  const backend = _getBackend();

  // ── Path A: keyring (retried) ──────────────────────────────────────────
  // A throw here means the keyring op FAILED — but on macOS/Windows that is
  // almost always a transiently locked Keychain (idle/just-woke machine), not
  // a missing backend. `read` returns `undefined` for "no such entry" (the
  // genuine first-run signal). So we retry on throw, and only a throw that
  // SURVIVES every attempt drops us to Path B.
  let keyringError: unknown;
  for (let attempt = 0; attempt < _keyringReadAttempts; attempt++) {
    try {
      const existing = await backend.read(NEW_SERVICE, ACCOUNT);
      if (existing) return _deserialize(existing);

      // A successful empty read is a genuine first run on a working keyring.
      // The Outpost-Pi hard cutover deliberately does not inspect legacy
      // remote-pi/keytar services.
      // Generate and save to the new service.
      const fresh = generateEd25519Keypair();
      await backend.write(NEW_SERVICE, ACCOUNT, _serialize(fresh));
      return fresh;
    } catch (err) {
      keyringError = err;
      if (attempt < _keyringReadAttempts - 1) {
        // Linear backoff — a locked Keychain usually frees within seconds.
        await _sleep(_keyringRetryDelayMs * (attempt + 1));
      }
    }
  }

  // ── Path B: keyring threw on every attempt ─────────────────────────────
  // If a file identity already exists, this machine is in file mode
  // (headless, or previously degraded) — use it, never regenerate.
  const fromFile = await _readKeypairFromFile();
  if (fromFile) return fromFile;

  // No file identity AND the keyring is unreadable. CRITICAL FORK:
  //
  //  - On a platform without a guaranteed keyring (headless Linux, no D-Bus),
  //    minting a file-backed identity is the documented, correct first-run
  //    behavior.
  //  - On macOS/Windows the keyring is a core OS service, so a persistent read
  //    failure means it's LOCKED/denied — NOT that we're a fresh install.
  //    Generating a new key here is exactly what silently broke pairing after
  //    a week idle, and the new key then masks the real Keychain identity via
  //    the file. So we FAIL LOUD instead, unless the operator explicitly
  //    opts into a file identity.
  const forceFile = process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY === "1";
  if (_keyringExpectedAvailable() && !forceFile) {
    throw new KeyringUnavailableError(keyringError);
  }

  console.warn(
    "[outpost-pi] keyring unavailable; using file-backed identity at " +
    `${IDENTITY_FILE}. ${String(keyringError)}`,
  );
  const fresh = generateEd25519Keypair();
  await _writeKeypairToFile(fresh);
  return fresh;
}

// ── peers.json ────────────────────────────────────────────────────────────────

/** Persist one Owner pairing and its Pi-relative protected-channel high-water state. */
export interface PeerRecord {
  name: string;
  remote_epk: string; // base64 standard, 32B Ed25519
  paired_at: string;  // ISO-8601
  /** Base64 of 64 bytes: Pi send key followed by Pi receive key. */
  channel_key?: string;
  /** Unsigned decimal uint64 high-water, encoded as a string to avoid JSON precision loss. */
  send_seq?: string;
  /** Unsigned decimal uint64 high-water, encoded as a string to avoid JSON precision loss. */
  recv_seq?: string;
}

/** Hold validated Pi-relative channel keys decoded from a peer record. */
export interface PeerChannelKeys {
  send: Uint8Array;
  recv: Uint8Array;
}

const MAX_UINT64 = (1n << 64n) - 1n;

/** Encode Pi-relative send and receive keys as one stable peers.json field. */
export function encodePeerChannelKeys(keys: PeerChannelKeys): string {
  if (keys.send.length !== 32 || keys.recv.length !== 32) {
    throw new Error("owner channel directional keys must each be 32 bytes");
  }
  return Buffer.concat([Buffer.from(keys.send), Buffer.from(keys.recv)]).toString("base64");
}

/** Decode and validate the persisted Pi-relative directional key material. */
export function decodePeerChannelKeys(channelKey: string | undefined): PeerChannelKeys | null {
  if (!channelKey) return null;
  const decoded = Buffer.from(channelKey, "base64");
  if (decoded.length !== 64 || decoded.toString("base64") !== channelKey) return null;
  return {
    send: Uint8Array.from(decoded.subarray(0, 32)),
    recv: Uint8Array.from(decoded.subarray(32, 64)),
  };
}

/** Parse a persisted decimal uint64 high-water, defaulting absent legacy fields to zero. */
export function parsePeerChannelSequence(value: string | undefined): bigint | null {
  if (value === undefined) return 0n;
  if (!/^(?:0|[1-9][0-9]*)$/.test(value)) return null;
  const parsed = BigInt(value);
  return parsed <= MAX_UINT64 ? parsed : null;
}

async function _hardenPeersFilePermissions(): Promise<void> {
  try { await chmod(PEERS_PATH, 0o600); } catch { /* missing/non-POSIX/not fatal */ }
}

async function _writePeersFile(peers: PeerRecord[]): Promise<void> {
  const dir = dirname(PEERS_PATH);
  await _ensurePrivateStorageDir(dir);
  const tmpPath = join(
    dir,
    `.peers.json.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    await writeFile(tmpPath, JSON.stringify({ peers }, null, 2), { mode: 0o600 });
    try { await chmod(tmpPath, 0o600); } catch { /* mode may be unsupported */ }
    await rename(tmpPath, PEERS_PATH);
    await _hardenPeersFilePermissions();
  } catch (err) {
    try { await unlink(tmpPath); } catch { /* temp file may not exist */ }
    throw err;
  }
}

/** Load the persisted pairing roster, returning an empty roster when it is absent or unreadable. */
export async function listPeers(): Promise<PeerRecord[]> {
  await _hardenPeersFilePermissions();
  try {
    const raw = await readFile(PEERS_PATH, "utf8");
    const parsed = JSON.parse(raw) as { peers: PeerRecord[] };
    return parsed.peers ?? [];
  } catch {
    return [];
  }
}

let _peerMutationTail: Promise<void> = Promise.resolve();

function _mutatePeers<T>(mutate: (peers: PeerRecord[]) => Promise<T> | T): Promise<T> {
  const operation = _peerMutationTail.then(async () => {
    const peers = await listPeers();
    return mutate(peers);
  });
  _peerMutationTail = operation.then(() => undefined, () => undefined);
  return operation;
}

/**
 * Persist a pairing record, replacing an existing entry for the same remote key atomically.
 *
 * @throws when the roster cannot be written.
 */
export function addPeer(record: PeerRecord): Promise<void> {
  return _mutatePeers(async (peers) => {
    const idx = peers.findIndex((p) => p.remote_epk === record.remote_epk);
    if (idx >= 0) {
      peers[idx] = record; // idempotent re-pair refreshes the channel key and counters
    } else {
      peers.push(record);
    }
    await _writePeersFile(peers);
  });
}

/**
 * Persist one or both sequence high-waters without overwriting a newer re-pair.
 *
 * The expected channel key fences queued writes from a detached channel after
 * the same Owner has established fresh key material.
 */
export function updatePeerChannelSequences(
  remoteEpk: string,
  expectedChannelKey: string,
  patch: { sendSeq?: bigint; recvSeq?: bigint },
): Promise<boolean> {
  return _mutatePeers(async (peers) => {
    const peer = peers.find((candidate) => candidate.remote_epk === remoteEpk);
    if (!peer || peer.channel_key !== expectedChannelKey) return false;
    for (const seq of [patch.sendSeq, patch.recvSeq]) {
      if (seq !== undefined && (seq < 0n || seq > MAX_UINT64)) {
        throw new RangeError("owner channel sequence must fit uint64");
      }
    }
    if (patch.sendSeq !== undefined) peer.send_seq = patch.sendSeq.toString(10);
    if (patch.recvSeq !== undefined) peer.recv_seq = patch.recvSeq.toString(10);
    await _writePeersFile(peers);
    return true;
  });
}

/**
 * Returns the set of distinct `remote_epk` values in peers.json.
 *
 * In the current pairing model (plan/23 + plan/24), each `remote_epk` is the
 * Owner's Ed25519 pubkey — and we treat each as a distinct Owner the Pi has
 * been paired with. Used by the mesh self-revoke poller (plan/24 Wave 3) to
 * know which Owners' mesh blobs to fetch.
 */
export async function listOwnerPubkeys(): Promise<string[]> {
  const peers = await listPeers();
  const seen = new Set<string>();
  for (const p of peers) seen.add(p.remote_epk);
  return [...seen];
}

/**
 * Remove every pairing record for a remote key and report whether the roster changed.
 *
 * @throws when the updated roster cannot be written.
 */
export function removePeer(remoteEpk: string): Promise<boolean> {
  return _mutatePeers(async (peers) => {
    const filtered = peers.filter((p) => p.remote_epk !== remoteEpk);
    if (filtered.length === peers.length) return false;
    await _writePeersFile(filtered);
    return true;
  });
}

// ── Test-only helpers ────────────────────────────────────────────────────────

/** Test-only: expose the identity-file path so tests can clean it. */
export const _IDENTITY_FILE_FOR_TEST = IDENTITY_FILE;
/** Test-only: expose unlink for cleanup. */
export const _unlinkIdentityFileForTest = async (): Promise<void> => {
  try { await unlink(IDENTITY_FILE); } catch { /* fine if missing */ }
};
