import { describe, expect, test, vi } from "vitest";
import { generateEd25519Keypair, ed25519Sign } from "../pairing/crypto.js";
import { canonicalBytes } from "./canonical.js";
import { SelfRevoke, type SelfRevokeStorage } from "./self_revoke.js";
import type { MeshClient } from "./client.js";
import type { MeshEnvelope } from "./types.js";

/** Builds a signed envelope from a logical header object. */
function makeEnvelope(
  ownerKp: { publicKey: Uint8Array; secretKey: Uint8Array },
  version: number,
  memberEpks: string[],
): MeshEnvelope {
  const blob = canonicalBytes({
    version,
    issued_at: Date.now(),
    owner_pk: Buffer.from(ownerKp.publicKey).toString("base64"),
    members: memberEpks.map((epk, i) => ({
      remote_epk: epk,
      relay_url: "wss://test",
      paired_at: `2026-05-22T0${i}:00:00Z`,
    })),
  });
  return { blob, sig: ed25519Sign(ownerKp.secretKey, blob) };
}

/** Storage + MeshClient fakes. Vitest mocks return promises so awaits work. */
function setup(opts: {
  envelope: MeshEnvelope | null;
  ownerEpks: string[];
}) {
  const storage: SelfRevokeStorage = {
    listOwnerPubkeys: vi.fn().mockResolvedValue(opts.ownerEpks),
    removePeer: vi.fn().mockResolvedValue(true),
  };
  const client = {
    get: vi.fn().mockResolvedValue(opts.envelope),
  } as unknown as MeshClient;
  const log = {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };
  const onRevoke = vi.fn().mockResolvedValue(undefined);
  return { storage, client, log, onRevoke };
}

/** Base64 standard → URL-safe (no padding). Mirrors how the app emits
 *  pubkeys in `members[].remote_epk` while the pi-ext uses standard. */
function toUrlSafe(stdB64: string): string {
  return stdB64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

describe("SelfRevoke.checkOnce — membership encoding variants", () => {
  test("(a) member in standard base64 + Pi pubkey bytes → does not revoke", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpkStd = Buffer.from(myKp.publicKey).toString("base64");

    const env = makeEnvelope(ownerKp, 1, [myEpkStd, "AAAAAAAA"]);
    const { storage, client, log, onRevoke } = setup({
      envelope: env,
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();

    expect(client.get).toHaveBeenCalledTimes(1);
    expect(storage.removePeer).not.toHaveBeenCalled();
    expect(onRevoke).not.toHaveBeenCalled();
    expect(log.error).not.toHaveBeenCalled();
  });

  test("(a-url-safe) member in URL-safe base64 + Pi in standard → does not revoke (THE BUG FIX)", async () => {
    // Reproduces the exact plan/24 W3 incident: app published with url-safe
    // encoding, pi-ext compared with standard, false revoke fired.
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpkUrlSafe = toUrlSafe(Buffer.from(myKp.publicKey).toString("base64"));

    const env = makeEnvelope(ownerKp, 1, [myEpkUrlSafe]);
    const { storage, client, log, onRevoke } = setup({
      envelope: env,
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();

    expect(storage.removePeer).not.toHaveBeenCalled();
    expect(onRevoke).not.toHaveBeenCalled();
    expect(log.info).not.toHaveBeenCalled();
  });

  test("(a-no-pad) member in standard base64 WITHOUT padding → does not revoke", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpkNoPad = Buffer.from(myKp.publicKey).toString("base64").replace(/=+$/, "");

    const env = makeEnvelope(ownerKp, 1, [myEpkNoPad]);
    const { storage, client, log, onRevoke } = setup({
      envelope: env,
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();

    expect(storage.removePeer).not.toHaveBeenCalled();
  });

  test("(b) myPubkey absent → removePeer + onRevoke + log info", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");

    // Members list does NOT include myKp.publicKey
    const env = makeEnvelope(ownerKp, 3, ["other-peer-1", "other-peer-2"]);
    const { storage, client, log, onRevoke } = setup({
      envelope: env,
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();

    expect(storage.removePeer).toHaveBeenCalledWith(ownerEpk);
    expect(onRevoke).toHaveBeenCalledWith(ownerEpk);
    expect(log.info).toHaveBeenCalledWith(
      expect.stringContaining("self-revoked from owner"),
    );
    // Log must surface the EXACT received version (3 here) and the `since`
    // cursor we sent (undefined on first poll → "<none>"). This lets the
    // operator cross-reference with a SQLite snapshot without ambiguity.
    expect(log.info).toHaveBeenCalledWith(
      expect.stringMatching(/received v3.*since=<none>.*members=2/),
    );
    expect(log.error).not.toHaveBeenCalled();
  });

  test("(c) 404 from relay → skip silently (no revoke, no error)", async () => {
    const myKp = generateEd25519Keypair();
    const ownerKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");

    const { storage, client, log, onRevoke } = setup({
      envelope: null, // client returns null for 304/404
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();

    expect(client.get).toHaveBeenCalledTimes(1);
    expect(storage.removePeer).not.toHaveBeenCalled();
    expect(onRevoke).not.toHaveBeenCalled();
    expect(log.error).not.toHaveBeenCalled();
    expect(log.warn).not.toHaveBeenCalled();
  });

  test("anti-rollback: lower version than last-seen is ignored", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpk = Buffer.from(myKp.publicKey).toString("base64");

    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: vi.fn().mockResolvedValue([ownerEpk]),
      removePeer: vi.fn().mockResolvedValue(true),
    };
    const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

    // First call returns v5 with me as member. Second call returns v3 with
    // me removed → should be rejected as rollback, no revoke.
    const envV5 = makeEnvelope(ownerKp, 5, [myEpk]);
    const envV3 = makeEnvelope(ownerKp, 3, []);
    const client = {
      get: vi.fn()
        .mockResolvedValueOnce(envV5)
        .mockResolvedValueOnce(envV3),
    } as unknown as MeshClient;
    const onRevoke = vi.fn();

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await revoker.checkOnce();
    await revoker.checkOnce();

    expect(storage.removePeer).not.toHaveBeenCalled();
    expect(onRevoke).not.toHaveBeenCalled();
    expect(log.warn).toHaveBeenCalledWith(expect.stringContaining("anti-rollback"));
  });

  test("malformed envelope → log.error, no throw, no revoke", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const badEnv: MeshEnvelope = {
      blob: new TextEncoder().encode("not json"),
      sig: new Uint8Array(64),
    };
    const { storage, client, log, onRevoke } = setup({
      envelope: badEnv,
      ownerEpks: [ownerEpk],
    });

    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, onRevoke, log,
    });
    await expect(revoker.checkOnce()).resolves.toBeUndefined();
    expect(log.error).toHaveBeenCalled();
    expect(storage.removePeer).not.toHaveBeenCalled();
  });
});

describe("SelfRevoke lifecycle", () => {
  test("onMembersChanged fires when sibling set changes across sweeps (plan/25 Wave D)", async () => {
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const siblingA = generateEd25519Keypair();
    const siblingB = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpk = Buffer.from(myKp.publicKey).toString("base64");
    const aEpk = Buffer.from(siblingA.publicKey).toString("base64");
    const bEpk = Buffer.from(siblingB.publicKey).toString("base64");

    // 1st sweep: members = [me, A]
    const env1 = makeEnvelope(ownerKp, 1, [myEpk, aEpk]);
    // 2nd sweep: identical members — no callback
    const env2 = makeEnvelope(ownerKp, 2, [myEpk, aEpk]);
    // 3rd sweep: members = [me, A, B] — callback fires
    const env3 = makeEnvelope(ownerKp, 3, [myEpk, aEpk, bEpk]);

    const get = vi.fn()
      .mockResolvedValueOnce(env1)
      .mockResolvedValueOnce(env2)
      .mockResolvedValueOnce(env3);
    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: vi.fn().mockResolvedValue([ownerEpk]),
      removePeer: vi.fn(),
    };
    const onMembersChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: { get } as unknown as MeshClient,
      storage,
      myPubkey: myKp.publicKey,
      onMembersChanged,
    });

    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(1);
    const first = onMembersChanged.mock.calls[0]![0] as { pcLabel: string; pcPubkey: string }[];
    expect(first.map((s) => s.pcPubkey).sort()).toEqual([aEpk].sort());

    await revoker.checkOnce();
    // No change → callback NOT fired again.
    expect(onMembersChanged).toHaveBeenCalledTimes(1);

    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(2);
    const third = onMembersChanged.mock.calls[1]![0] as { pcLabel: string; pcPubkey: string }[];
    expect(third.map((s) => s.pcPubkey).sort()).toEqual([aEpk, bEpk].sort());
  });

  test("onMembersChanged evicts siblings when their Owner revokes us (the not_authorized-loop bug)", async () => {
    // Reproduces story-extension-stale-sibling-evict-on-owner-revocation:
    // after re-pairing under a new Owner, the extension kept spamming
    // pi_envelope to a revoked sibling because SelfRevoke.membersByOwner
    // retained the revoked Owner's member list. listOwnerPubkeys() no longer
    // returns the Owner after removePeer, so _checkOwner never refreshed
    // its entry — but _computeSiblingUnion still iterates the stale entry,
    // keeping the revoked sibling in the union forever. onMembersChanged
    // never fires a shrink → setSiblings never evicts → not_authorized loop.
    //
    // The fix: delete membersByOwner[ownerEpk] BEFORE removePeer in
    // _checkOwner, so the union computation at the end of the SAME sweep
    // sees the eviction and fires onMembersChanged immediately — independent
    // of persistence. (checkOnce also reconciles membersByOwner against
    // listOwnerPubkeys at the top of each sweep for removal paths that
    // bypass _checkOwner.)
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const siblingA = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpk = Buffer.from(myKp.publicKey).toString("base64");
    const aEpk = Buffer.from(siblingA.publicKey).toString("base64");

    // 1st sweep: members = [me, A] — sibling A is discovered.
    const env1 = makeEnvelope(ownerKp, 1, [myEpk, aEpk]);
    // 2nd sweep: members = [A] (me removed) — this Pi is revoked.
    const env2 = makeEnvelope(ownerKp, 2, [aEpk]);

    const get = vi.fn()
      .mockResolvedValueOnce(env1)
      .mockResolvedValueOnce(env2);
    // After revocation, listOwnerPubkeys no longer returns the Owner
    // (removePeer removed it from peers.json). The 3rd sweep sees no owners.
    const owners = vi.fn()
      .mockResolvedValueOnce([ownerEpk])
      .mockResolvedValueOnce([ownerEpk])
      .mockResolvedValueOnce([]);
    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: owners,
      removePeer: vi.fn().mockResolvedValue(true),
    };
    const onMembersChanged = vi.fn();
    const onRevoke = vi.fn().mockResolvedValue(undefined);
    const revoker = new SelfRevoke({
      client: { get } as unknown as MeshClient,
      storage,
      myPubkey: myKp.publicKey,
      onMembersChanged,
      onRevoke,
    });

    // 1st sweep: sibling A discovered → onMembersChanged fires with [A].
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(1);
    const first = onMembersChanged.mock.calls[0]![0] as { pcPubkey: string }[];
    expect(first.map((s) => s.pcPubkey)).toEqual([aEpk]);

    // 2nd sweep: this Pi is revoked. The delete happens BEFORE removePeer,
    // so the union computation at the end of THIS sweep sees the eviction →
    // onMembersChanged fires with [] immediately (same-sweep convergence).
    // Without the fix, membersByOwner retains the stale [A] entry and
    // onMembersChanged does NOT fire a shrink → setSiblings never evicts A.
    await revoker.checkOnce();
    expect(onRevoke).toHaveBeenCalledWith(ownerEpk);
    expect(onMembersChanged).toHaveBeenCalledTimes(2);
    const afterRevoke = onMembersChanged.mock.calls[1]![0] as { pcPubkey: string }[];
    expect(afterRevoke).toEqual(
      [],
      "revoked Owner's siblings must be evicted same-sweep, not retained stale",
    );

    // 3rd sweep: listOwnerPubkeys omits the revoked Owner. The reconcile at
    // the top of checkOnce prunes any residual entry (belt-and-suspenders).
    // Union is still empty → onMembersChanged does NOT fire again.
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(2);
  });

  test("onMembersChanged evicts even when removePeer throws (in-memory invalidation is independent of persistence)", async () => {
    // The delete must happen BEFORE removePeer so a failed persistence
    // (disk full, permissions) doesn't leave stale siblings in the union.
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const siblingA = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpk = Buffer.from(myKp.publicKey).toString("base64");
    const aEpk = Buffer.from(siblingA.publicKey).toString("base64");

    const env1 = makeEnvelope(ownerKp, 1, [myEpk, aEpk]);
    const env2 = makeEnvelope(ownerKp, 2, [aEpk]); // me revoked

    const get = vi.fn()
      .mockResolvedValueOnce(env1)
      .mockResolvedValueOnce(env2);
    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: vi.fn().mockResolvedValue([ownerEpk]),
      removePeer: vi.fn().mockRejectedValue(new Error("EACCES: permission denied")),
    };
    const onMembersChanged = vi.fn();
    const onRevoke = vi.fn().mockResolvedValue(undefined);
    const revoker = new SelfRevoke({
      client: { get } as unknown as MeshClient,
      storage,
      myPubkey: myKp.publicKey,
      onMembersChanged,
      onRevoke,
      log: { info: () => {}, warn: () => {}, error: () => {} },
    });

    // 1st sweep: A discovered.
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(1);

    // 2nd sweep: revoke, but removePeer THROWS. The per-owner catch logs
    // the error. The delete already happened (before removePeer), so the
    // union is empty → onMembersChanged fires [] despite persistence failing.
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(2);
    const afterRevoke = onMembersChanged.mock.calls[1]![0] as { pcPubkey: string }[];
    expect(afterRevoke).toEqual(
      [],
      "in-memory eviction must not be gated on removePeer succeeding",
    );
  });

  test("onMembersChanged evicts siblings when an Owner is removed outside SelfRevoke (interactive unpair)", async () => {
    // The reconcile at the top of checkOnce prunes membersByOwner entries
    // for Owners no longer in listOwnerPubkeys — covers removal paths that
    // bypass _checkOwner (pairing_coordinator's interactive unpair calls
    // removePeer directly, without touching SelfRevoke state).
    const ownerKp = generateEd25519Keypair();
    const myKp = generateEd25519Keypair();
    const siblingA = generateEd25519Keypair();
    const ownerEpk = Buffer.from(ownerKp.publicKey).toString("base64");
    const myEpk = Buffer.from(myKp.publicKey).toString("base64");
    const aEpk = Buffer.from(siblingA.publicKey).toString("base64");

    const env1 = makeEnvelope(ownerKp, 1, [myEpk, aEpk]);

    const get = vi.fn().mockResolvedValue(env1);
    // 1st sweep: Owner present. 2nd sweep: Owner removed externally
    // (interactive unpair) — listOwnerPubkeys no longer returns it.
    const owners = vi.fn()
      .mockResolvedValueOnce([ownerEpk])
      .mockResolvedValueOnce([]);
    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: owners,
      removePeer: vi.fn().mockResolvedValue(true),
    };
    const onMembersChanged = vi.fn();
    const revoker = new SelfRevoke({
      client: { get } as unknown as MeshClient,
      storage,
      myPubkey: myKp.publicKey,
      onMembersChanged,
    });

    // 1st sweep: A discovered.
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(1);
    expect(
      (onMembersChanged.mock.calls[0]![0] as { pcPubkey: string }[]).map((s) => s.pcPubkey),
    ).toEqual([aEpk]);

    // 2nd sweep: Owner gone from listOwnerPubkeys (removed externally).
    // The reconcile prunes membersByOwner[owner] → union empty →
    // onMembersChanged fires [] → setSiblings evicts A. Without the
    // reconcile, the stale entry keeps A in the union forever.
    await revoker.checkOnce();
    expect(onMembersChanged).toHaveBeenCalledTimes(2);
    const afterRemove = onMembersChanged.mock.calls[1]![0] as { pcPubkey: string }[];
    expect(afterRemove).toEqual(
      [],
      "externally-removed Owner's siblings must be pruned by the reconcile",
    );
  });

  test("start() is idempotent and stop() clears the interval", async () => {
    const myKp = generateEd25519Keypair();
    // No owners → checkOnce is a fast no-op. We just verify the interval
    // is set/cleared by inspecting Node's setInterval bookkeeping.
    const storage: SelfRevokeStorage = {
      listOwnerPubkeys: vi.fn().mockResolvedValue([]),
      removePeer: vi.fn().mockResolvedValue(true),
    };
    const client = { get: vi.fn() } as unknown as MeshClient;
    const revoker = new SelfRevoke({
      client, storage, myPubkey: myKp.publicKey, intervalMs: 10_000,
    });

    const refsBefore = (process as unknown as { _getActiveHandles?: () => unknown[] })
      ._getActiveHandles?.().length ?? 0;

    revoker.start();
    revoker.start(); // idempotent — second start should not double-schedule

    // Let the immediate `void checkOnce()` settle so the spy sees the call.
    await new Promise<void>((r) => setImmediate(r));
    expect(storage.listOwnerPubkeys).toHaveBeenCalledTimes(1);

    revoker.stop();
    // After stop, no further intervals pending.
    const refsAfter = (process as unknown as { _getActiveHandles?: () => unknown[] })
      ._getActiveHandles?.().length ?? 0;
    expect(refsAfter).toBeLessThanOrEqual(refsBefore);
  });
});
