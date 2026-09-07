import { describe, expect, test, vi } from "vitest";
import {
  createFleetArmRestartHandler,
  FleetUpdateCoordinator,
  type FleetArmRestartAck,
  type FleetPeerAck,
  type FleetUpdateStatusEvent,
  isFleetArmRestartRequest,
  localPeerAddresses,
} from "./fleet_update.js";

type LogEntry =
  | { op: "emit"; event: FleetUpdateStatusEvent }
  | { op: "update" }
  | { op: "arm" }
  | { op: "peerList" }
  | { op: "mesh"; peer: string; body: unknown };

interface Harness {
  readonly log: LogEntry[];
  readonly coordinator: FleetUpdateCoordinator;
  resolveUpdate: (ok: boolean, outputTail?: string) => void;
  setPeers: (peers: string[]) => void;
  setAck: (peer: string, ack: unknown | null | Error) => void;
}

function harness(opts?: {
  updateTimeoutMs?: number;
  ackTimeoutMs?: number;
}): Harness {
  const log: LogEntry[] = [];
  let resolveUpdate!: (ok: boolean, outputTail?: string) => void;
  let peers: string[] = [];
  const acks = new Map<string, unknown | null | Error>();

  const coordinator = new FleetUpdateCoordinator({
    emitStatus: (event) => { log.push({ op: "emit", event }); },
    runUpdate: () => new Promise((resolve) => {
      log.push({ op: "update" });
      resolveUpdate = (ok, outputTail = "") => resolve({ ok, outputTail });
    }),
    armSelf: () => { log.push({ op: "arm" }); },
    localPeers: () => {
      log.push({ op: "peerList" });
      return peers;
    },
    meshRequest: async (peer, body, _timeoutMs) => {
      log.push({ op: "mesh", peer, body });
      const ack = acks.get(peer);
      if (ack instanceof Error) throw ack;
      return { ack: ack === undefined ? null : ack };
    },
    updateTimeoutMs: opts?.updateTimeoutMs,
    ackTimeoutMs: opts?.ackTimeoutMs,
  });

  return {
    log,
    coordinator,
    resolveUpdate: (ok, tail) => resolveUpdate(ok, tail),
    setPeers: (next) => { peers = next; },
    setAck: (peer, ack) => { acks.set(peer, ack); },
  };
}

function phases(log: LogEntry[]): string[] {
  return log
    .filter((entry): entry is { op: "emit"; event: FleetUpdateStatusEvent } => entry.op === "emit")
    .map((entry) => entry.event.phase);
}

describe("FleetUpdateCoordinator", () => {
  test("success path emits updating before the subprocess and arming after acks, arms self last", async () => {
    const h = harness();
    h.setPeers(["/vm@a"]);
    h.setAck("/vm@a", { state: "armed" });
    const run = h.coordinator.handleRequest("run-1");
    await Promise.resolve(); // let handleRequest reach the update await
    h.resolveUpdate(true);

    await run;

    const ops = h.log.map((entry) => entry.op);
    expect(ops.indexOf("update")).toBeGreaterThan(ops.indexOf("emit"));
    expect(phases(h.log)).toEqual(["updating", "arming"]);
    expect(ops.lastIndexOf("emit")).toBeLessThan(ops.indexOf("arm"));
    // Self-arm must be the final fleet action of the run.
    expect(ops.indexOf("arm")).toBe(ops.length - 1);
    const arming = h.log.find(
      (entry): entry is { op: "emit"; event: FleetUpdateStatusEvent } =>
        entry.op === "emit" && entry.event.phase === "arming",
    );
    expect(arming?.event.update_id).toBe("run-1");
    expect(arming?.event.peers).toEqual([{ peer: "/vm@a", state: "armed" }]);
    expect(h.coordinator.inFlightForTest()).toBe(false);
  });

  test("update failure stops the run: no peer list, no mesh request, no self-arm", async () => {
    const h = harness();
    const run = h.coordinator.handleRequest("run-fail");
    await Promise.resolve();
    h.resolveUpdate(false, "npm ERR! network");

    await run;

    expect(phases(h.log)).toEqual(["updating", "update_failed"]);
    const failed = h.log.at(-1);
    expect(failed).toMatchObject({
      op: "emit",
      event: { phase: "update_failed", detail: "npm ERR! network" },
    });
    expect(h.log.some((entry) => entry.op === "peerList")).toBe(false);
    expect(h.log.some((entry) => entry.op === "mesh")).toBe(false);
    expect(h.log.some((entry) => entry.op === "arm")).toBe(false);
  });

  test("second request while one runs answers already_running and never re-arms", async () => {
    const h = harness();
    const first = h.coordinator.handleRequest("run-1");
    await Promise.resolve(); // first run now inFlight inside the subprocess
    expect(h.coordinator.inFlightForTest()).toBe(true);

    await h.coordinator.handleRequest("run-2");
    expect(phases(h.log)).toEqual(["updating", "already_running"]);
    const second = h.log.at(-1);
    expect(second).toMatchObject({
      op: "emit",
      event: { phase: "already_running", update_id: "run-2" },
    });

    h.resolveUpdate(true);
    await first;
    expect(h.log.some((entry) => entry.op === "arm")).toBe(true); // only the first run armed
    expect(h.log.filter((entry) => entry.op === "arm")).toHaveLength(1);

    // The gate reopens after the first run finishes.
    const third = h.coordinator.handleRequest("run-3");
    await Promise.resolve();
    expect(h.coordinator.inFlightForTest()).toBe(true);
    h.resolveUpdate(true);
    await third;
    expect(phases(h.log)).toEqual(["updating", "already_running", "arming", "updating", "arming"]);
  });

  test("ack table carries armed, deferred, declined, and no-ack rows", async () => {
    const h = harness();
    h.setPeers(["/vm@armed", "/vm@deferred", "/vm@declined", "/vm@silent", "/vm@throws", "/vm@dupe", "/vm@dupe"]);
    h.setAck("/vm@armed", { state: "armed" });
    h.setAck("/vm@deferred", { state: "deferred", reason: "turn active" });
    h.setAck("/vm@declined", { state: "declined", reason: "hot-reload disabled" });
    h.setAck("/vm@silent", null); // reply envelope without a usable ack body
    h.setAck("/vm@throws", new Error("request to /vm@throws timed out after 5ms"));

    const run = h.coordinator.handleRequest("run-acks");
    await Promise.resolve();
    h.resolveUpdate(true);
    await run;

    const arming = h.log.find(
      (entry): entry is { op: "emit"; event: FleetUpdateStatusEvent } =>
        entry.op === "emit" && entry.event.phase === "arming",
    );
    const peers: FleetPeerAck[] = arming?.event.peers ?? [];
    expect(peers).toEqual([
      { peer: "/vm@armed", state: "armed" },
      { peer: "/vm@deferred", state: "deferred", reason: "turn active" },
      { peer: "/vm@declined", state: "declined", reason: "hot-reload disabled" },
      { peer: "/vm@silent", state: "no-ack", reason: "timeout" },
      { peer: "/vm@throws", state: "no-ack", reason: "request to /vm@throws timed out after 5ms" },
      { peer: "/vm@dupe", state: "no-ack", reason: "timeout" }, // duplicate roster entry collapsed
    ]);
  });

  test("mesh body is the arm-restart request for the run id", async () => {
    const h = harness();
    h.setPeers(["/vm@a"]);
    h.setAck("/vm@a", { state: "armed" });
    const run = h.coordinator.handleRequest("run-body");
    await Promise.resolve();
    h.resolveUpdate(true);
    await run;

    const meshes = h.log.filter(
      (entry): entry is { op: "mesh"; peer: string; body: unknown } => entry.op === "mesh",
    );
    expect(meshes[0]?.body).toEqual({
      kind: "outpost-pi.arm-restart.prepare",
      update_id: "run-body",
    });
    expect(meshes.at(-1)?.body).toEqual({
      kind: "outpost-pi.arm-restart.commit",
      update_id: "run-body",
    });
  });

  test("hung subprocess is failed by the update timeout without arming", async () => {
    vi.useFakeTimers();
    try {
      const h = harness({ updateTimeoutMs: 1_000 });
      const run = h.coordinator.handleRequest("run-hang");
      await vi.advanceTimersByTimeAsync(1_000);
      await run;

      expect(phases(h.log)).toEqual(["updating", "update_failed"]);
      expect(h.log.at(-1)).toMatchObject({
        op: "emit",
        event: { phase: "update_failed", detail: "pi update timed out" },
      });
      expect(h.log.some((entry) => entry.op === "arm")).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  test("failing localPeers yields an empty arming table instead of blocking the run", async () => {
    const log: LogEntry[] = [];
    const coordinator = new FleetUpdateCoordinator({
      emitStatus: (event) => { log.push({ op: "emit", event }); },
      runUpdate: () => {
        log.push({ op: "update" });
        return Promise.resolve({ ok: true, outputTail: "" });
      },
      armSelf: () => { log.push({ op: "arm" }); },
      localPeers: () => { throw new Error("broker unreachable"); },
      meshRequest: async () => null,
    });
    await coordinator.handleRequest("run-nolist");
    const arming = log.find(
      (entry): entry is { op: "emit"; event: FleetUpdateStatusEvent } =>
        entry.op === "emit" && entry.event.phase === "arming",
    );
    expect(arming?.event.peers).toEqual([]);
    expect(log.some((entry) => entry.op === "arm")).toBe(true);
  });

  test("coordinator reports a no-restart result after the arming report", async () => {
    const log: LogEntry[] = [];
    const coordinator = new FleetUpdateCoordinator({
      emitStatus: (event) => { log.push({ op: "emit", event }); },
      runUpdate: async () => ({ ok: true, outputTail: "" }),
      armSelf: () => ({ ok: false, reason: "hot-reload disabled" }),
      localPeers: () => [],
      meshRequest: async () => null,
    });

    await coordinator.handleRequest("run-no-restart");

    expect(phases(log)).toEqual(["updating", "arming", "update_failed"]);
    expect(log.at(-1)).toMatchObject({
      op: "emit",
      event: {
        phase: "update_failed",
        detail: "fleet restart not armed: hot-reload disabled",
      },
    });
  });

  test("update_failed detail is truncated to a bounded output tail", async () => {
    const h = harness();
    const run = h.coordinator.handleRequest("run-tail");
    await Promise.resolve();
    h.resolveUpdate(false, "x".repeat(10_000));
    await run;
    const failed = h.log.at(-1);
    expect(failed).toMatchObject({ op: "emit" });
    if (failed?.op === "emit") {
      expect(failed.event.detail?.length).toBe(4_000);
      expect(failed.event.detail).toBe("x".repeat(4_000));
    }
  });
});

describe("createFleetArmRestartHandler", () => {
  function handler(overrides?: Partial<{
    isDisposed: boolean;
    hotReloadEnabled: boolean;
    hasActiveWork: boolean;
    armResult: boolean;
  }>) {
    const arm = vi.fn(() => overrides?.armResult ?? true);
    const ack: FleetArmRestartAck = createFleetArmRestartHandler({
      isDisposed: () => overrides?.isDisposed ?? false,
      hotReloadEnabled: () => overrides?.hotReloadEnabled ?? true,
      hasActiveWork: () => overrides?.hasActiveWork ?? false,
      arm,
    })();
    return { ack, arm };
  }

  test("arms when enabled and idle", () => {
    const { ack, arm } = handler();
    expect(arm).toHaveBeenCalledTimes(1);
    expect(ack).toEqual({ state: "armed" });
  });

  test("prepare reports readiness without arming; commit arms exactly once", () => {
    const arm = vi.fn(() => true);
    let consumed = false;
    const handle = createFleetArmRestartHandler({
      isDisposed: () => false,
      hotReloadEnabled: () => true,
      hasActiveWork: () => false,
      consumeUpdate: () => {
        if (consumed) return false;
        consumed = true;
        return true;
      },
      arm,
    });

    expect(handle("run-two-phase", "prepare")).toEqual({ state: "armed" });
    expect(arm).not.toHaveBeenCalled();
    expect(handle("run-two-phase", "commit")).toEqual({ state: "armed" });
    expect(arm).toHaveBeenCalledWith("run-two-phase");
    expect(handle("run-two-phase", "commit")).toEqual({
      state: "declined",
      reason: "update already consumed",
    });
    expect(arm).toHaveBeenCalledTimes(1);
  });

  test("stages the arm and reports deferred while a turn is active", () => {
    const { ack, arm } = handler({ hasActiveWork: true });
    expect(arm).toHaveBeenCalledTimes(1); // deferred still stages the armed file
    expect(ack).toEqual({ state: "deferred", reason: "turn active" });
  });

  test("declines with reason when disposed, never writing the armed file", () => {
    const { ack, arm } = handler({ isDisposed: true });
    expect(arm).not.toHaveBeenCalled();
    expect(ack).toEqual({ state: "declined", reason: "disposed" });
  });

  test("declines with reason when the host toggle is off", () => {
    const { ack, arm } = handler({ hotReloadEnabled: false });
    expect(arm).not.toHaveBeenCalled();
    expect(ack).toEqual({ state: "declined", reason: "hot-reload disabled" });
  });

  test("declines with reason when the armed file could not be written", () => {
    const { ack, arm } = handler({ armResult: false });
    expect(arm).toHaveBeenCalledTimes(1);
    expect(ack).toEqual({ state: "declined", reason: "arm failed" });
  });
});

describe("isFleetArmRestartRequest", () => {
  test("accepts a well-formed request and rejects everything else", () => {
    expect(isFleetArmRestartRequest({ kind: "outpost-pi.arm-restart", update_id: "u1" })).toBe(true);
    expect(isFleetArmRestartRequest({ kind: "outpost-pi.arm-restart", update_id: "" })).toBe(false);
    expect(isFleetArmRestartRequest({ kind: "other", update_id: "u1" })).toBe(false);
    expect(isFleetArmRestartRequest({ kind: "outpost-pi.arm-restart" })).toBe(false);
    expect(isFleetArmRestartRequest(null)).toBe(false);
    expect(isFleetArmRestartRequest("outpost-pi.arm-restart")).toBe(false);
  });
});

describe("localPeerAddresses", () => {
  test("keeps structured roster entries without a pc label", () => {
    const body = {
      peers: ["/vm@a", "pc2:/vm@b", "/vm@c"],
      peers_detailed: [
        { cwd: "/vm", name: "a", address: "/vm@a" },
        { pc: "pc2", cwd: "/vm", name: "b", address: "pc2:/vm@b" },
        { pc: "", cwd: "/vm", name: "c", address: "/vm@c" }, // falsy pc → local (matches the join handler)
      ],
    };
    expect(localPeerAddresses(body)).toEqual(["/vm@a", "/vm@c"]);
  });

  test("falls back to the legacy address heuristic without peers_detailed", () => {
    expect(localPeerAddresses({ peers: ["/vm@a", "pc2:/vm@b"] })).toEqual(["/vm@a"]);
    expect(localPeerAddresses({ peers: [] })).toEqual([]);
  });

  test("returns null when the reply carries no roster", () => {
    expect(localPeerAddresses(null)).toBeNull();
    expect(localPeerAddresses({})).toBeNull();
    expect(localPeerAddresses({ error: "unavailable" })).toBeNull();
  });
});
