import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Tests import the module after stubbing `os.homedir` so the fallback
// path writes inside a temp dir instead of the dev's real ~/.pi/remote.
// vi.mock must run before the real module load.
const _tmpHome = mkdtempSync(join(tmpdir(), "pi-storage-"));
const PEERS_DIR_FOR_TEST = join(_tmpHome, ".pi", "remote");
const PEERS_FILE_FOR_TEST = join(PEERS_DIR_FOR_TEST, "peers.json");
const PEERS_LOCK_FOR_TEST = join(PEERS_DIR_FOR_TEST, "peers.lock");
vi.mock("node:os", async (importOriginal) => {
  const orig = await importOriginal<typeof import("node:os")>();
  return { ...orig, homedir: () => _tmpHome };
});

// Re-import after the mock is installed.
const storage = await import("./storage.js");
const {
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  _setKeyStoreBackendForTest,
  _setKeyringExpectedForTest,
  _setKeyringRetryForTest,
  _setKeyringOperationTimeoutForTest,
  _setNativeBindingErrorForTest,
  _unlinkIdentityFileForTest,
  _IDENTITY_FILE_FOR_TEST,
  withKeyStoreOperationTimeout,
  PairedIdentityMissingError,
  addPeer,
  listPeers,
  encodePeerChannelKeys,
  decodePeerChannelKeys,
  parsePeerChannelSequence,
  reserveSendSeq,
  compareAndAdvanceRecvSeq,
  PeerStorage,
  PeerStorageLockTimeoutError,
} = storage;
import type { KeyStoreBackend } from "./storage.js";

// ── In-memory backend for round-trip tests ──────────────────────────────────

class InMemoryBackend implements KeyStoreBackend {
  readonly store = new Map<string, string>();
  readonly reads: { service: string; account: string }[] = [];
  readonly writes: { service: string; account: string; value: string }[] = [];
  readonly deletes: { service: string; account: string }[] = [];
  private _failOn?: "read" | "write" | "delete";
  private _failAllOn?: "read" | "write" | "delete";

  failNext(op: "read" | "write" | "delete" | undefined) {
    this._failOn = op;
  }

  /** Persistent failure — every op of this kind throws (simulates a keyring
   *  that's locked/unavailable for the whole call, surviving retries). */
  failAll(op: "read" | "write" | "delete" | undefined) {
    this._failAllOn = op;
  }

  async read(service: string, account: string) {
    this.reads.push({ service, account });
    if (this._failAllOn === "read") throw new Error("simulated keyring locked");
    if (this._failOn === "read") {
      this._failOn = undefined;
      throw new Error("simulated keyring unavailable");
    }
    return this.store.get(`${service}|${account}`);
  }
  async write(service: string, account: string, value: string) {
    this.writes.push({ service, account, value });
    if (this._failOn === "write") {
      this._failOn = undefined;
      throw new Error("simulated keyring write failure");
    }
    this.store.set(`${service}|${account}`, value);
  }
  async delete(service: string, account: string) {
    this.deletes.push({ service, account });
    const key = `${service}|${account}`;
    const had = this.store.has(key);
    this.store.delete(key);
    return had;
  }
}

const NEW_SERVICE = "dev.outpostpi.pi";
const ACCOUNT = "longterm-ed25519";
const POSIX_MODES_SUPPORTED = process.platform !== "win32";

function expectPrivateFileMode(path: string): void {
  if (!POSIX_MODES_SUPPORTED) return;
  expect(statSync(path).mode & 0o777).toBe(0o600);
}

function expectPrivateDirMode(path: string): void {
  if (!POSIX_MODES_SUPPORTED) return;
  expect(statSync(path).mode & 0o777).toBe(0o700);
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((res) => { resolve = res; });
  return { promise, resolve };
}

const PHONE_PEER = {
  name: "phone",
  remote_epk: Buffer.from(new Uint8Array(32).fill(11)).toString("base64"),
  paired_at: "2026-06-28T00:00:00.000Z",
};

const TABLET_PEER = {
  name: "tablet",
  remote_epk: Buffer.from(new Uint8Array(32).fill(12)).toString("base64"),
  paired_at: "2026-06-28T00:01:00.000Z",
};

beforeEach(async () => {
  // Silence fallback console output during tests so the vitest output isn't
  // polluted.
  vi.spyOn(console, "info").mockImplementation(() => undefined);
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  vi.spyOn(console, "error").mockImplementation(() => undefined);
  // Zero retry delay so persistent-failure tests don't sleep.
  _setKeyringRetryForTest(3, 0);
  await _unlinkIdentityFileForTest();
  rmSync(PEERS_FILE_FOR_TEST, { force: true });
  rmSync(PEERS_LOCK_FOR_TEST, { recursive: true, force: true });
});

afterEach(() => {
  _setKeyStoreBackendForTest(null);
  _setKeyringExpectedForTest(null);
  _setKeyringRetryForTest(null);
  _setKeyringOperationTimeoutForTest(null);
  _setNativeBindingErrorForTest(null);
  delete process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY;
  vi.restoreAllMocks();
});

// ── Keyring path ────────────────────────────────────────────────────────────

describe("keyring operation timeout", () => {
  test("bounds hanging read, write, and delete operations", async () => {
    const never = new Promise<never>(() => undefined);
    const hanging: KeyStoreBackend = {
      read: () => never,
      write: () => never,
      delete: () => never,
    };
    const bounded = withKeyStoreOperationTimeout(hanging, 10);

    await Promise.all([
      expect(bounded.read(NEW_SERVICE, ACCOUNT)).rejects.toThrow("read(dev.outpostpi.pi) timed out"),
      expect(bounded.write(NEW_SERVICE, ACCOUNT, "secret")).rejects.toThrow("write(dev.outpostpi.pi) timed out"),
      expect(bounded.delete(NEW_SERVICE, ACCOUNT)).rejects.toThrow("delete(dev.outpostpi.pi) timed out"),
    ]);
  });
});

describe("getOrCreateEd25519Keypair — keyring path", () => {
  test("returns existing entry from new service without writing", async () => {
    const backend = new InMemoryBackend();
    const original = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(2)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, original);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
    );
    expect(backend.writes.length).toBe(0);
    expect(backend.deletes.length).toBe(0);
  });

  test("generates + saves a fresh keypair when neither service has an entry", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey).toBeInstanceOf(Uint8Array);
    expect(kp.publicKey.length).toBe(32);
    expect(backend.writes.length).toBe(1);
    expect(backend.writes[0]!.service).toBe(NEW_SERVICE);
    expect(backend.writes[0]!.account).toBe(ACCOUNT);
    expect(backend.deletes.length).toBe(0);
  });

  test("legacy keyring identity (dev.remotepi.mac) is ignored after the destructive Outpost-Pi cutover", async () => {
    // The rebrand removed the mac→pi migration (hard cutover, no read-old
    // path). This pins that a legacy entry is neither read nor adopted: the
    // lookup only touches dev.outpostpi.pi and mints a fresh identity there.
    const backend = new InMemoryBackend();
    const legacyIdentity = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(9)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(9)).toString("base64"),
    });
    backend.store.set(`dev.remotepi.mac|${ACCOUNT}`, legacyIdentity);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();

    // Only the new service was read — the legacy mac service was never probed.
    expect(backend.reads.map((r) => r.service)).toEqual([NEW_SERVICE]);
    // A fresh identity was generated + written to the new service.
    expect(backend.writes).toContainEqual(
      expect.objectContaining({ service: NEW_SERVICE, account: ACCOUNT }),
    );
    // The generated key is NOT the legacy key.
    expect(Buffer.from(kp.publicKey).toString("base64")).not.toBe(
      Buffer.from(new Uint8Array(32).fill(9)).toString("base64"),
    );
    // The legacy entry was never deleted (no migration cleanup path).
    expect(backend.deletes).toEqual([]);
  });

  test("idempotent across two calls — second call returns same key without write", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const first = await getOrCreateEd25519Keypair();
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
    expect(backend.writes.length).toBe(1);  // only the first call wrote
  });
});

// ── Headless fallback ───────────────────────────────────────────────────────

describe("getOrCreateEd25519Keypair — headless Linux fallback", () => {
  test("keyring read throws persistently (no keyring expected) → falls back to identity.json (chmod 0o600)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(false);  // simulate headless Linux (no core keyring)

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey.length).toBe(32);

    // File exists at the expected path with restrictive perms.
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
    // POSIX-only: `chmod 0o600` is a no-op on Windows (NTFS perms aren't the
    // POSIX bits + Node reports a fixed mode), so only assert the perm bits
    // off Windows. The file-creation + fallback behavior is checked above.
    if (process.platform !== "win32") {
      const stat = statSync(_IDENTITY_FILE_FOR_TEST);
      const perms = stat.mode & 0o777;
      expect(perms & 0o077).toBe(0);  // group + other bits zero
    }

    // Round-trip: parse and check it deserializes to the same key.
    const parsed = JSON.parse(readFileSync(_IDENTITY_FILE_FOR_TEST, "utf8")) as { pk: string; sk: string };
    expect(Buffer.from(parsed.pk, "base64").length).toBe(32);
  });

  test("fallback second call returns the file-stored key (no regen)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(false);
    const first = await getOrCreateEd25519Keypair();

    // Reset the backend so it would throw again on a fresh read.
    const backend2 = new InMemoryBackend();
    backend2.failAll("read");
    _setKeyStoreBackendForTest(backend2);
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
  });

});

// ── peers.json permissions ──────────────────────────────────────────────────

describe("peers.json storage permissions", () => {
  test("addPeer writes peers.json with private file and parent directory permissions", async () => {
    await addPeer(PHONE_PEER);

    expect(existsSync(PEERS_FILE_FOR_TEST)).toBe(true);
    const parsed = JSON.parse(readFileSync(PEERS_FILE_FOR_TEST, "utf8")) as { peers: unknown[] };
    expect(parsed.peers).toEqual([PHONE_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
    expectPrivateDirMode(PEERS_DIR_FOR_TEST);
  });

  test("listPeers hardens an existing permissive peers.json on read", async () => {
    mkdirSync(PEERS_DIR_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(PEERS_FILE_FOR_TEST, JSON.stringify({ peers: [PHONE_PEER] }, null, 2), { mode: 0o644 });
    if (POSIX_MODES_SUPPORTED) chmodSync(PEERS_FILE_FOR_TEST, 0o644);

    const peers = await listPeers();

    expect(peers).toEqual([PHONE_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
  });

  test("channel key and decimal uint64 high-waters survive a storage restart", async () => {
    const send = new Uint8Array(32).fill(21);
    const recv = new Uint8Array(32).fill(22);
    const channelKey = encodePeerChannelKeys({ send, recv });
    await addPeer({
      ...PHONE_PEER,
      channel_key: channelKey,
      send_seq: "9007199254740992",
      recv_seq: "0",
    });

    expect(await reserveSendSeq(PHONE_PEER.remote_epk, channelKey)).toBe(9_007_199_254_740_993n);
    expect(await compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, channelKey, 42n)).toBe("accepted");

    // Re-read from disk rather than retaining the object passed to addPeer.
    const [reloaded] = await listPeers();
    expect(reloaded).toMatchObject({
      channel_key: channelKey,
      send_seq: "9007199254740993",
      recv_seq: "42",
    });
    expect(decodePeerChannelKeys(reloaded!.channel_key)).toEqual({ send, recv });
    expect(parsePeerChannelSequence(reloaded!.send_seq)).toBe(9_007_199_254_740_993n);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
  });

  test("independent stores reserve unique send sequences and stale instances self-correct", async () => {
    const channelKey = encodePeerChannelKeys({
      send: new Uint8Array(32).fill(31),
      recv: new Uint8Array(32).fill(32),
    });
    const first = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    const stale = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await first.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });
    expect((await stale.listPeers())[0]?.send_seq).toBe("0");

    const reservations = await Promise.all(
      Array.from({ length: 100 }, (_, index) =>
        (index % 2 === 0 ? first : stale).reserveSendSeq(PHONE_PEER.remote_epk, channelKey)
      ),
    );
    expect(new Set(reservations).size).toBe(100);
    expect(reservations.map((value) => value!).sort((a, b) => a < b ? -1 : 1)).toEqual(
      Array.from({ length: 100 }, (_, index) => BigInt(index + 1)),
    );

    const advanced = await first.reserveSendSeq(PHONE_PEER.remote_epk, channelKey);
    expect(advanced).toBe(101n);
    expect(await stale.reserveSendSeq(PHONE_PEER.remote_epk, channelKey)).toBe(102n);
    expect((await first.listPeers())[0]?.send_seq).toBe("102");
  });

  test("stale receive submissions are rejected instead of max-merged as success", async () => {
    const channelKey = encodePeerChannelKeys({
      send: new Uint8Array(32).fill(41),
      recv: new Uint8Array(32).fill(42),
    });
    const first = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    const stale = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await first.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });

    expect(await first.compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, channelKey, 700n))
      .toBe("accepted");
    // A stale channel must not receive a successful no-op: callers use this
    // result as the authority to dispatch security-sensitive owner actions.
    expect(await stale.compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, channelKey, 3n))
      .toBe("replay");
    expect((await stale.listPeers())[0]?.recv_seq).toBe("700");
  });

  test("concurrent duplicate receive delivery is accepted exactly once across stores", async () => {
    const channelKey = encodePeerChannelKeys({
      send: new Uint8Array(32).fill(43),
      recv: new Uint8Array(32).fill(44),
    });
    const first = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    const second = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await first.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });

    const results = await Promise.all([
      first.compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, channelKey, 9n),
      second.compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, channelKey, 9n),
    ]);

    expect(results.filter((result) => result === "accepted")).toHaveLength(1);
    expect(results.filter((result) => result === "replay")).toHaveLength(1);
    expect((await first.listPeers())[0]?.recv_seq).toBe("9");
  });

  test("stale channel operations cannot overwrite freshly re-paired key material", async () => {
    const oldKey = encodePeerChannelKeys({ send: new Uint8Array(32).fill(1), recv: new Uint8Array(32).fill(2) });
    const freshKey = encodePeerChannelKeys({ send: new Uint8Array(32).fill(3), recv: new Uint8Array(32).fill(4) });
    await addPeer({ ...PHONE_PEER, channel_key: oldKey, send_seq: "0", recv_seq: "0" });
    await addPeer({ ...PHONE_PEER, channel_key: freshKey, send_seq: "0", recv_seq: "0" });

    expect(await reserveSendSeq(PHONE_PEER.remote_epk, oldKey)).toBeNull();
    expect(await compareAndAdvanceRecvSeq(PHONE_PEER.remote_epk, oldKey, 99n))
      .toBe("stale_generation");
    expect((await listPeers())[0]).toMatchObject({ channel_key: freshKey, send_seq: "0", recv_seq: "0" });
  });

  test("reclaims an old lock owned by a dead process", async () => {
    const channelKey = encodePeerChannelKeys({ send: new Uint8Array(32).fill(51), recv: new Uint8Array(32).fill(52) });
    const store = new PeerStorage({ directory: PEERS_DIR_FOR_TEST, lockTimeoutMs: 100, lockRetryMs: 1, lockStaleMs: 10 });
    await store.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });
    mkdirSync(PEERS_LOCK_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(
      join(PEERS_LOCK_FOR_TEST, "owner.json"),
      JSON.stringify({ pid: 2_147_483_647, token: "dead-owner-generation" }),
    );
    const old = new Date(Date.now() - 1_000);
    utimesSync(PEERS_LOCK_FOR_TEST, old, old);

    await expect(store.reserveSendSeq(PHONE_PEER.remote_epk, channelKey)).resolves.toBe(1n);
    expect(existsSync(PEERS_LOCK_FOR_TEST)).toBe(false);
  });

  test("respects an old lock owned by a live process and fails after a bounded wait", async () => {
    const channelKey = encodePeerChannelKeys({ send: new Uint8Array(32).fill(61), recv: new Uint8Array(32).fill(62) });
    const seed = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await seed.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });
    mkdirSync(PEERS_LOCK_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(
      join(PEERS_LOCK_FOR_TEST, "owner.json"),
      JSON.stringify({ pid: process.pid, token: "live-owner-generation" }),
    );
    const old = new Date(Date.now() - 1_000);
    utimesSync(PEERS_LOCK_FOR_TEST, old, old);
    const contender = new PeerStorage({
      directory: PEERS_DIR_FOR_TEST,
      lockTimeoutMs: 25,
      lockRetryMs: 2,
      lockStaleMs: 10,
    });

    await expect(contender.reserveSendSeq(PHONE_PEER.remote_epk, channelKey))
      .rejects.toBeInstanceOf(PeerStorageLockTimeoutError);
    expect(JSON.parse(readFileSync(PEERS_FILE_FOR_TEST, "utf8")).peers[0].send_seq).toBe("0");
    expect(existsSync(PEERS_LOCK_FOR_TEST)).toBe(true);
  });

  test("a delayed holder release cannot remove a successor lock generation", async () => {
    const channelKey = encodePeerChannelKeys({
      send: new Uint8Array(32).fill(69),
      recv: new Uint8Array(32).fill(70),
    });
    const seed = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await seed.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });

    const holderAcquired = deferred<void>();
    const releaseHolder = deferred<void>();
    const holder = new PeerStorage({
      directory: PEERS_DIR_FOR_TEST,
      lockHooks: {
        afterLockOwnerWritten: async () => {
          holderAcquired.resolve();
          await releaseHolder.promise;
        },
      },
    });
    const reservation = holder.reserveSendSeq(PHONE_PEER.remote_epk, channelKey);
    await holderAcquired.promise;

    const displacedPath = `${PEERS_LOCK_FOR_TEST}.displaced`;
    renameSync(PEERS_LOCK_FOR_TEST, displacedPath);
    mkdirSync(PEERS_LOCK_FOR_TEST, { mode: 0o700 });
    const successorOwner = JSON.stringify({ pid: process.pid, token: "successor-after-holder" });
    writeFileSync(join(PEERS_LOCK_FOR_TEST, "owner.json"), successorOwner);

    releaseHolder.resolve();
    await expect(reservation).resolves.toBe(1n);
    expect(readFileSync(join(PEERS_LOCK_FOR_TEST, "owner.json"), "utf8")).toBe(successorOwner);

    rmSync(PEERS_LOCK_FOR_TEST, { recursive: true, force: true });
    rmSync(displacedPath, { recursive: true, force: true });
  });

  test("a delayed second reclaimer cannot rename a live successor lock generation", async () => {
    const channelKey = encodePeerChannelKeys({
      send: new Uint8Array(32).fill(71),
      recv: new Uint8Array(32).fill(72),
    });
    const seed = new PeerStorage({ directory: PEERS_DIR_FOR_TEST });
    await seed.addPeer({ ...PHONE_PEER, channel_key: channelKey, send_seq: "0", recv_seq: "0" });
    mkdirSync(PEERS_LOCK_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(
      join(PEERS_LOCK_FOR_TEST, "owner.json"),
      JSON.stringify({ pid: 2_147_483_647, token: "dead-before-aba" }),
    );
    const old = new Date(Date.now() - 1_000);
    utimesSync(PEERS_LOCK_FOR_TEST, old, old);

    const delayedClassified = deferred<void>();
    const resumeDelayed = deferred<void>();
    const delayedMarkedSuccessor = deferred<void>();
    let pauseFirstClassification = true;
    let committedReclaims = 0;
    const delayed = new PeerStorage({
      directory: PEERS_DIR_FOR_TEST,
      lockTimeoutMs: 2_000,
      lockRetryMs: 1,
      lockStaleMs: 0,
      lockHooks: {
        afterReclaimClassified: async () => {
          if (!pauseFirstClassification) return;
          pauseFirstClassification = false;
          delayedClassified.resolve();
          await resumeDelayed.promise;
        },
        afterReclaimMarkerCreated: () => delayedMarkedSuccessor.resolve(),
        onReclaimCommitted: () => { committedReclaims += 1; },
      },
    });
    const delayedReservation = delayed.reserveSendSeq(PHONE_PEER.remote_epk, channelKey);
    await delayedClassified.promise;

    const winner = new PeerStorage({
      directory: PEERS_DIR_FOR_TEST,
      lockStaleMs: 0,
      lockHooks: { onReclaimCommitted: () => { committedReclaims += 1; } },
    });
    await expect(winner.reserveSendSeq(PHONE_PEER.remote_epk, channelKey)).resolves.toBe(1n);

    const successorHeld = deferred<void>();
    const releaseSuccessor = deferred<void>();
    const successor = new PeerStorage({
      directory: PEERS_DIR_FOR_TEST,
      lockHooks: {
        afterLockOwnerWritten: async () => {
          successorHeld.resolve();
          await releaseSuccessor.promise;
        },
      },
    });
    const successorReservation = successor.reserveSendSeq(PHONE_PEER.remote_epk, channelKey);
    await successorHeld.promise;
    const successorOwner = readFileSync(join(PEERS_LOCK_FOR_TEST, "owner.json"), "utf8");

    resumeDelayed.resolve();
    await delayedMarkedSuccessor.promise;
    await vi.waitFor(() => {
      expect(readFileSync(join(PEERS_LOCK_FOR_TEST, "owner.json"), "utf8")).toBe(successorOwner);
      expect(existsSync(join(PEERS_LOCK_FOR_TEST, "reclaim"))).toBe(false);
    });
    expect(committedReclaims).toBe(1);

    releaseSuccessor.resolve();
    await expect(successorReservation).resolves.toBe(2n);
    await expect(delayedReservation).resolves.toBe(3n);
    expect(committedReclaims).toBe(1);
    expect((await seed.listPeers())[0]?.send_seq).toBe("3");
  });

  test("addPeer migrates an existing permissive peers.json on update", async () => {
    mkdirSync(PEERS_DIR_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(PEERS_FILE_FOR_TEST, JSON.stringify({ peers: [PHONE_PEER] }, null, 2), { mode: 0o644 });
    if (POSIX_MODES_SUPPORTED) chmodSync(PEERS_FILE_FOR_TEST, 0o644);

    await addPeer(TABLET_PEER);

    const parsed = JSON.parse(readFileSync(PEERS_FILE_FOR_TEST, "utf8")) as { peers: unknown[] };
    expect(parsed.peers).toEqual([PHONE_PEER, TABLET_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
  });
});

describe("getOrCreateEd25519Keypair — identity precedence and binding fallback", () => {
  async function seedFileIdentity() {
    const unavailable = new InMemoryBackend();
    unavailable.failAll("read");
    _setKeyStoreBackendForTest(unavailable);
    _setKeyringExpectedForTest(false);
    return getOrCreateEd25519Keypair();
  }

  test("an existing file identity wins without consulting a readable different keyring", async () => {
    const fileIdentity = await seedFileIdentity();
    const keyring = new InMemoryBackend();
    keyring.store.set(`${NEW_SERVICE}|${ACCOUNT}`, JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(42)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(43)).toString("base64"),
    }));
    _setKeyStoreBackendForTest(keyring);
    _setKeyringExpectedForTest(true);

    const resolved = await getOrCreateEd25519Keypair();

    expect(Buffer.from(resolved.publicKey)).toEqual(Buffer.from(fileIdentity.publicKey));
    expect(keyring.reads).toEqual([]);
    expect(keyring.writes).toEqual([]);
  });

  test("a native binding load failure is non-fatal and uses the file fallback", async () => {
    _setNativeBindingErrorForTest(new Error("Cannot find native binding"));
    _setKeyringRetryForTest(1, 0);
    _setKeyringOperationTimeoutForTest(20);

    const resolved = await getOrCreateEd25519Keypair();

    expect(resolved.publicKey).toHaveLength(32);
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
  });
});

describe("getOrCreateEd25519Keypair — existing pairings prevent identity replacement", () => {
  test("an unreadable keyring cannot mint a file identity over paired devices", async () => {
    await addPeer(PHONE_PEER);
    const unavailable = new InMemoryBackend();
    unavailable.failAll("read");
    _setKeyStoreBackendForTest(unavailable);
    _setKeyringExpectedForTest(false);

    await expect(getOrCreateEd25519Keypair()).rejects.toBeInstanceOf(PairedIdentityMissingError);
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(false);
  });

  test("an empty alternate keyring cannot mint over paired devices", async () => {
    await addPeer(PHONE_PEER);
    const empty = new InMemoryBackend();
    _setKeyStoreBackendForTest(empty);

    await expect(getOrCreateEd25519Keypair()).rejects.toBeInstanceOf(PairedIdentityMissingError);
    expect(empty.writes).toEqual([]);
  });

  test("the explicit file-identity escape hatch remains available", async () => {
    await addPeer(PHONE_PEER);
    const unavailable = new InMemoryBackend();
    unavailable.failAll("read");
    _setKeyStoreBackendForTest(unavailable);
    _setKeyringExpectedForTest(false);
    process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY = "1";

    await expect(getOrCreateEd25519Keypair()).resolves.toMatchObject({ publicKey: expect.any(Uint8Array) });
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
  });
});

// ── Locked-keychain protection (the "lost pairing after a week idle" bug) ────

describe("getOrCreateEd25519Keypair — locked keyring does NOT regenerate", () => {
  test("transient read failure recovers via retry → uses keyring entry, no file written", async () => {
    const backend = new InMemoryBackend();
    const original = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(5)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(6)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, original);
    backend.failNext("read");  // first read throws, retry succeeds
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);  // macOS/Windows: keyring is core

    const kp = await getOrCreateEd25519Keypair();
    // Recovered the ORIGINAL paired key — not a freshly minted one.
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(5)).toString("base64"),
    );
    expect(backend.reads.length).toBeGreaterThanOrEqual(2);  // retried
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(false);  // no file regen
  });

  test("persistent failure on a core-keyring platform with no file → throws (refuses to regen)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);  // macOS/Windows

    await expect(getOrCreateEd25519Keypair()).rejects.toBeInstanceOf(KeyringUnavailableError);
    // Critically: no new identity file was written (pairing not silently broken).
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(false);
  });

  test("persistent failure but identity.json already exists → returns the FILE key (never throws, never regen)", async () => {
    // First, create a file identity via the headless path.
    const seed = new InMemoryBackend();
    seed.failAll("read");
    _setKeyStoreBackendForTest(seed);
    _setKeyringExpectedForTest(false);
    const fileKp = await getOrCreateEd25519Keypair();

    // Now the keyring is "core" but locked; the existing file must win.
    const locked = new InMemoryBackend();
    locked.failAll("read");
    _setKeyStoreBackendForTest(locked);
    _setKeyringExpectedForTest(true);
    const kp = await getOrCreateEd25519Keypair();

    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(fileKp.publicKey).toString("base64"),
    );
  });

  test("OUTPOST_PI_ALLOW_FILE_IDENTITY=1 opts into file identity even on a core-keyring platform", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);
    process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY = "1";

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey.length).toBe(32);
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
  });
});
