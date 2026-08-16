import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile, chmod, unlink, rename, rm, stat, open } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
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

/** Refuse identity replacement when the persisted pairing roster proves one already existed. */
export class PairedIdentityMissingError extends Error {
  constructor(pairedCount: number, cause: unknown) {
    super(
      `No identity could be read, but ${pairedCount} device(s) are already paired. ` +
      "Refusing to generate a new identity because that would revoke every paired device. " +
      "Give this process access to the original keyring, or install the original keypair " +
      "at ~/.pi/remote/identity.json with mode 0600. " +
      `Cause: ${String(cause)}`,
    );
    this.name = "PairedIdentityMissingError";
  }
}

const PI_DIR = join(homedir(), ".pi", "remote");
const IDENTITY_FILE = join(PI_DIR, "identity.json");

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

const KEYRING_OPERATION_TIMEOUT_MS = 3_000;
let _keyringOperationTimeoutMs = KEYRING_OPERATION_TIMEOUT_MS;

function _withTimeout<T>(operation: Promise<T>, label: string, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error(`keyring ${label} timed out after ${timeoutMs}ms`)),
      timeoutMs,
    );
    operation.then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (error: unknown) => {
        clearTimeout(timeout);
        reject(error);
      },
    );
  });
}

/** Bound every operation on a credential backend so a native hang cannot strand pairing startup. */
export function withKeyStoreOperationTimeout(
  backend: KeyStoreBackend,
  timeoutMs = KEYRING_OPERATION_TIMEOUT_MS,
): KeyStoreBackend {
  return {
    read: (service, account) => _withTimeout(
      Promise.resolve().then(() => backend.read(service, account)),
      `read(${service})`,
      timeoutMs,
    ),
    write: (service, account, value) => _withTimeout(
      Promise.resolve().then(() => backend.write(service, account, value)),
      `write(${service})`,
      timeoutMs,
    ),
    delete: (service, account) => _withTimeout(
      Promise.resolve().then(() => backend.delete(service, account)),
      `delete(${service})`,
      timeoutMs,
    ),
  };
}

let _asyncEntryCtor: typeof import("@napi-rs/keyring").AsyncEntry | null = null;
let _nativeBindingError: unknown = null;

async function _loadAsyncEntry(): Promise<typeof import("@napi-rs/keyring").AsyncEntry> {
  if (_asyncEntryCtor) return _asyncEntryCtor;
  if (_nativeBindingError) throw _nativeBindingError;
  try {
    const module = await import("@napi-rs/keyring");
    _asyncEntryCtor = module.AsyncEntry;
    return _asyncEntryCtor;
  } catch (error) {
    _nativeBindingError = error;
    throw error;
  }
}

function _nativeBindingUnavailable(): boolean {
  return _nativeBindingError !== null;
}

class NapiKeyringBackend implements KeyStoreBackend {
  async read(service: string, account: string): Promise<string | undefined> {
    const AsyncEntry = await _loadAsyncEntry();
    return new AsyncEntry(service, account).getPassword();
  }
  async write(service: string, account: string, value: string): Promise<void> {
    const AsyncEntry = await _loadAsyncEntry();
    await new AsyncEntry(service, account).setPassword(value);
  }
  async delete(service: string, account: string): Promise<boolean> {
    try {
      const AsyncEntry = await _loadAsyncEntry();
      return await new AsyncEntry(service, account).deleteCredential();
    } catch {
      return false;
    }
  }
}

let _backend: KeyStoreBackend | null = null;

function _getBackend(): KeyStoreBackend {
  if (!_backend) {
    _backend = withKeyStoreOperationTimeout(new NapiKeyringBackend(), _keyringOperationTimeoutMs);
  }
  return _backend;
}

/** Test-only: swap (or clear with `null`) the keyring backend. */
export function _setKeyStoreBackendForTest(backend: KeyStoreBackend | null): void {
  _backend = backend
    ? withKeyStoreOperationTimeout(backend, _keyringOperationTimeoutMs)
    : null;
}

/** Test-only: tune operation deadlines without waiting for the production timeout. */
export function _setKeyringOperationTimeoutForTest(timeoutMs: number | null): void {
  _keyringOperationTimeoutMs = timeoutMs ?? KEYRING_OPERATION_TIMEOUT_MS;
  _backend = null;
}

/** Test-only: emulate a runtime where the native keyring binding cannot load. */
export function _setNativeBindingErrorForTest(error: unknown): void {
  _asyncEntryCtor = null;
  _nativeBindingError = error;
  _backend = null;
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
  if (_nativeBindingUnavailable()) return false;
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

/**
 * Mint-once file identity (O_EXCL, "wx"): the FIRST concurrent first-run
 * caller wins; the rest get EEXIST and re-read the winner's key.
 *
 * A plain writeFile here let two concurrent first-run callers (e.g. the
 * fire-and-forget session-start auto-start racing a typed `/outpost-pi`, or
 * the daemon-start timer) mint DIFFERENT identities on a fresh HOME —
 * whichever key the pairing QR was built from could then reference a relay
 * connection the other start had already superseded, silently killing
 * pairing with no error on either side (see
 * backlog-pairing-e2e-flaky-auth-handshake-timeout for the full forensics).
 */
async function _mintKeypairToFileExclusive(): Promise<Ed25519Keypair> {
  const fresh = generateEd25519Keypair();
  await _ensurePrivateStorageDir(PI_DIR);
  try {
    const handle = await open(IDENTITY_FILE, "wx", 0o600);
    try {
      await handle.writeFile(_serialize(fresh), "utf8");
    } finally {
      await handle.close();
    }
    return fresh;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    // A concurrent first-run minter won the O_EXCL race and may still be
    // mid-write — a zero-byte/partial read here would otherwise throw and
    // fail the caller. Retry briefly; the winner's single small write completes
    // within microseconds-to-milliseconds.
    for (let attempt = 0; attempt < 5; attempt++) {
      const winner = await _readKeypairFromFile();
      if (winner) return winner;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    const winner = await _readKeypairFromFile();
    if (winner) return winner;
    throw error;
  }
}

// ── Public API ──────────────────────────────────────────────────────────────

/**
 * Returns the Pi-secret Ed25519 keypair, generating + persisting one on
 * first call. Resolution order:
 *   1. Existing file `~/.pi/remote/identity.json`. File mode is sticky because
 *      that is the identity against which existing devices paired.
 *   2. Keyring service `dev.outpostpi.pi` (read retried — a transiently
 *      locked Keychain throws; we don't treat that as "no key").
 *   3. Generate a fresh keypair only when no pairing roster proves that an
 *      earlier identity existed. On macOS/Windows a persistent read failure
 *      throws `KeyringUnavailableError`; headless platforms use the exclusive
 *      file mint. `OUTPOST_PI_ALLOW_FILE_IDENTITY=1` is the explicit recovery
 *      escape hatch.
 *
 * Idempotent: subsequent calls return the same identity.
 */
export async function getOrCreateEd25519Keypair(): Promise<Ed25519Keypair> {
  // A file-backed installation must stay file-backed even if a keyring later
  // becomes readable. Consulting a stale or empty keyring first can mask the
  // identity against which the devices paired.
  const existingFile = await _readKeypairFromFile();
  if (existingFile) return existingFile;

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

      // A successful empty read is a genuine first run only when there is no
      // pairing roster. An alternate daemon/keyring context can read an empty
      // store even though devices are already paired to the original identity.
      const paired = await listPeers();
      if (paired.length > 0) {
        throw new PairedIdentityMissingError(paired.length, "keyring returned no identity");
      }

      // The Outpost-Pi hard cutover deliberately does not inspect legacy
      // remote-pi/keytar services.
      const fresh = generateEd25519Keypair();
      await backend.write(NEW_SERVICE, ACCOUNT, _serialize(fresh));
      return fresh;
    } catch (err) {
      if (err instanceof PairedIdentityMissingError) throw err;
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
  if (!forceFile) {
    const paired = await listPeers();
    if (paired.length > 0) {
      throw new PairedIdentityMissingError(paired.length, keyringError);
    }
  }
  if (_keyringExpectedAvailable() && !forceFile) {
    throw new KeyringUnavailableError(keyringError);
  }

  console.warn(
    _nativeBindingUnavailable()
      ? "[outpost-pi] @napi-rs/keyring could not load in this runtime; using " +
        `file-backed identity at ${IDENTITY_FILE} with mode 0600. ${String(keyringError)}`
      : "[outpost-pi] keyring unavailable; using file-backed identity at " +
        `${IDENTITY_FILE}. ${String(keyringError)}`,
  );
  return _mintKeypairToFileExclusive();
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

const DEFAULT_PEER_LOCK_TIMEOUT_MS = 2_000;
const DEFAULT_PEER_LOCK_RETRY_MS = 10;
const DEFAULT_PEER_LOCK_STALE_MS = 30_000;

/** Deterministic test seams around machine-lock ownership transitions. */
export interface PeerStorageLockHooks {
  afterReclaimClassified?(): Promise<void> | void;
  afterReclaimMarkerCreated?(): Promise<void> | void;
  afterReclaimRenamed?(): Promise<void> | void;
  afterLockOwnerWritten?(): Promise<void> | void;
  onReclaimCommitted?(): Promise<void> | void;
}

/** Tune one process-local peer store and its machine-wide mutation lock. */
export interface PeerStorageOptions {
  directory?: string;
  lockTimeoutMs?: number;
  lockRetryMs?: number;
  lockStaleMs?: number;
  /** Test-only hooks; production callers leave this absent. */
  lockHooks?: PeerStorageLockHooks;
}

/** Authoritative result of one locked Owner-to-Pi replay comparison. */
export type RecvSeqAdvanceResult = "accepted" | "replay" | "stale_generation";

interface PeerLockOwner {
  pid: number;
  token: string;
}

/** Raised when another live process holds the peers.json mutation lock beyond the bounded wait. */
export class PeerStorageLockTimeoutError extends Error {
  constructor(lockPath: string, timeoutMs: number) {
    super(`timed out after ${timeoutMs}ms acquiring peer storage lock ${lockPath}`);
    this.name = "PeerStorageLockTimeoutError";
  }
}

function _hasErrorCode(error: unknown, code: string): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

function _pidIsAlive(pid: number): boolean {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return !(typeof error === "object" && error !== null && "code" in error && error.code === "ESRCH");
  }
}

/**
 * Serialize peers.json read-modify-write operations across every local Pi process.
 *
 * Each instance retains its own promise tail for in-process ordering. Beneath that
 * tail, an atomic-mkdir lock protects the shared file. Old locks are reclaimed only
 * when both their mtime is stale and their recorded PID is no longer live.
 */
export class PeerStorage {
  private readonly peersPath: string;
  private readonly lockPath: string;
  private readonly lockOwnerPath: string;
  private readonly lockReclaimPath: string;
  private readonly lockTimeoutMs: number;
  private readonly lockRetryMs: number;
  private readonly lockStaleMs: number;
  private readonly lockHooks: PeerStorageLockHooks | undefined;
  private mutationTail: Promise<void> = Promise.resolve();

  constructor(options: PeerStorageOptions = {}) {
    const directory = options.directory ?? PI_DIR;
    this.peersPath = join(directory, "peers.json");
    this.lockPath = join(directory, "peers.lock");
    this.lockOwnerPath = join(this.lockPath, "owner.json");
    this.lockReclaimPath = join(this.lockPath, "reclaim");
    this.lockTimeoutMs = options.lockTimeoutMs ?? DEFAULT_PEER_LOCK_TIMEOUT_MS;
    this.lockRetryMs = options.lockRetryMs ?? DEFAULT_PEER_LOCK_RETRY_MS;
    this.lockStaleMs = options.lockStaleMs ?? DEFAULT_PEER_LOCK_STALE_MS;
    this.lockHooks = options.lockHooks;
  }

  /** Load a snapshot after every earlier operation accepted by this instance settles. */
  listPeers(): Promise<PeerRecord[]> {
    return this.serialize(() => this.readPeersFile());
  }

  /** Replace or append one Owner pairing without clobbering concurrent sequence state. */
  addPeer(record: PeerRecord): Promise<void> {
    return this.mutatePeers(async (peers) => {
      const idx = peers.findIndex((peer) => peer.remote_epk === record.remote_epk);
      if (idx >= 0) peers[idx] = record;
      else peers.push(record);
      await this.writePeersFile(peers);
    });
  }

  /**
   * Atomically reserve and persist the next Pi-to-Owner sequence.
   *
   * @returns the durable reserved value, or `null` when the peer/key generation no longer matches
   * @throws {RangeError} when the persisted uint64 sequence is exhausted
   * @throws {PeerStorageLockTimeoutError} when a live holder outlasts the bounded lock wait
   */
  reserveSendSeq(remoteEpk: string, expectedChannelKey: string): Promise<bigint | null> {
    return this.mutatePeers(async (peers) => {
      const peer = peers.find((candidate) => candidate.remote_epk === remoteEpk);
      if (!peer || peer.channel_key !== expectedChannelKey) return null;
      const stored = parsePeerChannelSequence(peer.send_seq);
      if (stored === null) return null;
      if (stored === MAX_UINT64) throw new RangeError("owner channel send sequence exhausted uint64");
      const reserved = stored + 1n;
      peer.send_seq = reserved.toString(10);
      await this.writePeersFile(peers);
      return reserved;
    });
  }

  /**
   * Compare and advance one Owner-to-Pi sequence under the machine-wide lock.
   *
   * The key-generation fence and replay comparison occur in the same critical
   * section as the durable write, so this result is the dispatch authority.
   *
   * @returns `accepted` only when this call durably advanced the high-water
   * @throws {RangeError} when the submitted sequence is outside uint64
   * @throws {PeerStorageLockTimeoutError} when a live holder outlasts the bounded lock wait
   */
  compareAndAdvanceRecvSeq(
    remoteEpk: string,
    expectedChannelKey: string,
    recvSeq: bigint,
  ): Promise<RecvSeqAdvanceResult> {
    return this.mutatePeers(async (peers) => {
      const peer = peers.find((candidate) => candidate.remote_epk === remoteEpk);
      if (!peer || peer.channel_key !== expectedChannelKey) return "stale_generation";
      if (recvSeq < 0n || recvSeq > MAX_UINT64) {
        throw new RangeError("owner channel receive sequence must fit uint64");
      }
      const stored = parsePeerChannelSequence(peer.recv_seq);
      if (stored === null) throw new Error("persisted owner channel receive sequence is invalid");
      if (recvSeq <= stored) return "replay";
      peer.recv_seq = recvSeq.toString(10);
      await this.writePeersFile(peers);
      return "accepted";
    });
  }

  /** Remove every pairing for one remote key without clobbering concurrent sequence state. */
  removePeer(remoteEpk: string): Promise<boolean> {
    return this.mutatePeers(async (peers) => {
      const filtered = peers.filter((peer) => peer.remote_epk !== remoteEpk);
      if (filtered.length === peers.length) return false;
      await this.writePeersFile(filtered);
      return true;
    });
  }

  private serialize<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.mutationTail.then(operation);
    this.mutationTail = result.then(() => undefined, () => undefined);
    return result;
  }

  private mutatePeers<T>(mutate: (peers: PeerRecord[]) => Promise<T> | T): Promise<T> {
    return this.serialize(() => this.withFileLock(async () => mutate(await this.readPeersFile())));
  }

  private async withFileLock<T>(operation: () => Promise<T>): Promise<T> {
    await _ensurePrivateStorageDir(dirname(this.peersPath));
    const deadline = Date.now() + this.lockTimeoutMs;
    let ownerToken = "";
    while (true) {
      try {
        await mkdir(this.lockPath, { mode: 0o700 });
        ownerToken = this.newLockToken();
        try {
          await writeFile(
            this.lockOwnerPath,
            JSON.stringify({ pid: process.pid, token: ownerToken } satisfies PeerLockOwner),
            { mode: 0o600 },
          );
        } catch (error) {
          // A reclaimer may have moved this just-created directory before the
          // owner write completed. Never path-remove a generation we cannot
          // identify: a later stale pass can safely reclaim the orphan.
          await this.removeLockIfOwned(ownerToken);
          throw error;
        }
        break;
      } catch (error) {
        if (!_hasErrorCode(error, "EEXIST")) throw error;
        if (await this.reclaimStaleLock()) continue;
        const remaining = deadline - Date.now();
        if (remaining <= 0) throw new PeerStorageLockTimeoutError(this.lockPath, this.lockTimeoutMs);
        await _sleep(Math.min(this.lockRetryMs, remaining));
      }
    }

    try {
      await this.lockHooks?.afterLockOwnerWritten?.();
      return await operation();
    } finally {
      // Release is generation-fenced. A delayed holder can never recursively
      // remove a successor's directory after its own lock was moved/replaced.
      await this.removeLockIfOwned(ownerToken);
    }
  }

  /**
   * Reclaim exactly the stale lock generation inspected by this contender.
   *
   * Two reclaimers cannot both advance: the fixed O_EXCL marker gives one the
   * generation while the other backs off. A holder release before the owner
   * re-read makes the inspected token disappear (or exposes a successor token),
   * so this reclaimer removes only its marker and aborts. A new acquirer between
   * that re-read and the path rename is the ABA case: moved owner+marker
   * verification detects the successor and restores it immediately. The normal
   * holder's release is independently token-fenced, so it cannot remove a
   * successor after its directory was moved. Thus only the inspected dead
   * generation is deleted. A process that dies between mkdir and writing
   * `owner.json` has no token, so that one legacy/incomplete case is fenced by
   * the directory's device+inode identity instead.
   */
  private async reclaimStaleLock(): Promise<boolean> {
    let lockStat;
    try {
      lockStat = await stat(this.lockPath);
    } catch (error) {
      return _hasErrorCode(error, "ENOENT");
    }
    if (Date.now() - lockStat.mtimeMs < this.lockStaleMs) return false;

    const inspectedOwner = await this.readLockOwner(this.lockOwnerPath);
    if (inspectedOwner && _pidIsAlive(inspectedOwner.pid)) return false;
    await this.lockHooks?.afterReclaimClassified?.();

    const markerToken = this.newLockToken();
    try {
      await writeFile(this.lockReclaimPath, markerToken, { encoding: "utf8", mode: 0o600, flag: "wx" });
    } catch (error) {
      if (_hasErrorCode(error, "ENOENT")) return true;
      if (_hasErrorCode(error, "EEXIST")) return false;
      throw error;
    }
    await this.lockHooks?.afterReclaimMarkerCreated?.();

    const confirmedOwner = await this.readLockOwner(this.lockOwnerPath);
    let confirmedStat;
    try {
      confirmedStat = await stat(this.lockPath);
    } catch (error) {
      await this.removeReclaimMarkerIfOwned(markerToken);
      return _hasErrorCode(error, "ENOENT");
    }
    const sameInspectedGeneration = inspectedOwner
      ? confirmedOwner?.token === inspectedOwner.token
      : !confirmedOwner && confirmedStat.dev === lockStat.dev && confirmedStat.ino === lockStat.ino;
    if (!sameInspectedGeneration || (confirmedOwner && _pidIsAlive(confirmedOwner.pid))) {
      await this.removeReclaimMarkerIfOwned(markerToken);
      return false;
    }

    const quarantinePath = `${this.lockPath}.quarantine.${markerToken.replaceAll(":", ".")}`;
    try {
      await rename(this.lockPath, quarantinePath);
    } catch (error) {
      await this.removeReclaimMarkerIfOwned(markerToken);
      return _hasErrorCode(error, "ENOENT");
    }
    await this.lockHooks?.afterReclaimRenamed?.();

    const movedOwner = await this.readLockOwner(join(quarantinePath, "owner.json"));
    const movedMarker = await this.readText(join(quarantinePath, "reclaim"));
    const movedStat = await stat(quarantinePath);
    const movedInspectedGeneration = inspectedOwner
      ? movedOwner?.token === inspectedOwner.token
      : !movedOwner && movedStat.dev === lockStat.dev && movedStat.ino === lockStat.ino;
    if (!movedInspectedGeneration || movedMarker !== markerToken) {
      // The path changed after our pre-rename owner check: this is a successor,
      // not the dead generation we classified. Restore it; never delete it.
      await rename(quarantinePath, this.lockPath);
      return false;
    }

    await rm(quarantinePath, { recursive: true, force: true });
    await this.lockHooks?.onReclaimCommitted?.();
    return true;
  }

  private newLockToken(): string {
    return `${process.pid}:${randomBytes(16).toString("hex")}`;
  }

  private async readLockOwner(path: string): Promise<PeerLockOwner | null> {
    try {
      const parsed = JSON.parse(await readFile(path, "utf8")) as { pid?: unknown; token?: unknown };
      if (
        typeof parsed.pid !== "number" ||
        !Number.isSafeInteger(parsed.pid) ||
        parsed.pid <= 0 ||
        typeof parsed.token !== "string" ||
        parsed.token.length === 0
      ) return null;
      return { pid: parsed.pid, token: parsed.token };
    } catch {
      return null;
    }
  }

  private async readText(path: string): Promise<string | null> {
    try { return await readFile(path, "utf8"); } catch { return null; }
  }

  private async removeLockIfOwned(ownerToken: string): Promise<void> {
    if (!ownerToken) return;
    const owner = await this.readLockOwner(this.lockOwnerPath);
    if (owner?.token !== ownerToken) return;
    await rm(this.lockPath, { recursive: true, force: true });
  }

  private async removeReclaimMarkerIfOwned(markerToken: string): Promise<void> {
    if (await this.readText(this.lockReclaimPath) !== markerToken) return;
    try { await unlink(this.lockReclaimPath); } catch { /* moved/released concurrently */ }
  }

  private async hardenPeersFilePermissions(): Promise<void> {
    try { await chmod(this.peersPath, 0o600); } catch { /* missing/non-POSIX/not fatal */ }
  }

  private async writePeersFile(peers: PeerRecord[]): Promise<void> {
    const dir = dirname(this.peersPath);
    await _ensurePrivateStorageDir(dir);
    const tmpPath = join(
      dir,
      `.peers.json.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`,
    );
    try {
      await writeFile(tmpPath, JSON.stringify({ peers }, null, 2), { mode: 0o600 });
      try { await chmod(tmpPath, 0o600); } catch { /* mode may be unsupported */ }
      await rename(tmpPath, this.peersPath);
      await this.hardenPeersFilePermissions();
    } catch (error) {
      try { await unlink(tmpPath); } catch { /* temp file may not exist */ }
      throw error;
    }
  }

  private async readPeersFile(): Promise<PeerRecord[]> {
    await this.hardenPeersFilePermissions();
    try {
      const raw = await readFile(this.peersPath, "utf8");
      const parsed = JSON.parse(raw) as { peers: PeerRecord[] };
      return parsed.peers ?? [];
    } catch {
      return [];
    }
  }
}

const defaultPeerStorage = new PeerStorage();

/** Load the persisted machine pairing roster. */
export function listPeers(): Promise<PeerRecord[]> {
  return defaultPeerStorage.listPeers();
}

/** Persist one Owner pairing through the machine-wide roster lock. */
export function addPeer(record: PeerRecord): Promise<void> {
  return defaultPeerStorage.addPeer(record);
}

/**
 * Reserve and persist the next Pi-to-Owner sequence before frame sealing.
 *
 * @throws when lock acquisition or durable persistence fails
 */
export function reserveSendSeq(remoteEpk: string, expectedChannelKey: string): Promise<bigint | null> {
  return defaultPeerStorage.reserveSendSeq(remoteEpk, expectedChannelKey);
}

/**
 * Atomically compare and advance one Owner-to-Pi replay high-water.
 *
 * @returns the authoritative dispatch decision for the submitted frame
 * @throws when lock acquisition or durable persistence fails
 */
export function compareAndAdvanceRecvSeq(
  remoteEpk: string,
  expectedChannelKey: string,
  recvSeq: bigint,
): Promise<RecvSeqAdvanceResult> {
  return defaultPeerStorage.compareAndAdvanceRecvSeq(remoteEpk, expectedChannelKey, recvSeq);
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
  return defaultPeerStorage.removePeer(remoteEpk);
}

// ── Test-only helpers ────────────────────────────────────────────────────────

/** Test-only: expose the identity-file path so tests can clean it. */
export const _IDENTITY_FILE_FOR_TEST = IDENTITY_FILE;
/** Test-only: expose unlink for cleanup. */
export const _unlinkIdentityFileForTest = async (): Promise<void> => {
  try { await unlink(IDENTITY_FILE); } catch { /* fine if missing */ }
};
