import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import type { MeshNode } from "../../session/mesh_node.js";
import type {
  LocalMeshCommands as LocalMeshCommandsClass,
  LocalMeshCommandsDeps,
} from "./local_mesh_commands.js";

let prevHome: string | undefined;
let isolatedRoot = "";
let LocalMeshCommandsCtor: typeof LocalMeshCommandsClass;

function createProjectCwd(name: string): string {
  const cwd = mkdtempSync(join(isolatedRoot, `proj-${name}-`));
  mkdirSync(join(cwd, ".pi", "outpost-pi"), { recursive: true });
  writeFileSync(
    join(cwd, ".pi", "outpost-pi", "config.json"),
    JSON.stringify({ agent_name: name, auto_start_relay: false }),
  );
  return cwd;
}

function makeHarness(cwd: string) {
  let node: MeshNode | null = null;
  let disposed = false;
  const setMeshNodeCalls: Array<MeshNode | null> = [];
  const notifications: string[] = [];
  let attachBridgeCalls = 0;

  const deps: LocalMeshCommandsDeps = {
    isDisposed: () => disposed,
    getState: () => "idle",
    meshNode: () => node,
    setMeshNode: (n) => {
      node = n;
      setMeshNodeCalls.push(n);
    },
    setSessionState: vi.fn(),
    startRelay: vi.fn(async () => undefined),
    stopRelay: vi.fn(async () => undefined),
    status: vi.fn(),
    controlCtx: () => ({ cwd, ui: { notify: (m: string) => { notifications.push(m); } } }) as never,
    emitRelayState: vi.fn(),
    refreshFooter: vi.fn(),
    refreshSessionPeerCount: vi.fn(),
    deliverMeshMessage: vi.fn(),
    attachBridgeIfReady: () => { attachBridgeCalls++; },
    notify: (m) => { notifications.push(m); },
    emitStatusEvent: vi.fn(() => true),
  };

  const ctx = {
    cwd,
    ui: {
      notify: (m: string) => { notifications.push(m); },
      setStatus: vi.fn(),
      setTitle: vi.fn(),
    },
  } as never;

  const commands = new LocalMeshCommandsCtor(deps);
  return {
    commands,
    ctx,
    getNode: () => node,
    setDisposed: (v: boolean) => { disposed = v; },
    setMeshNodeCalls,
    notifications,
    getAttachBridgeCalls: () => attachBridgeCalls,
  };
}

describe("LocalMeshCommands single-flight join hardening", () => {
  const cleanups: Array<() => Promise<void> | void> = [];

  beforeAll(async () => {
    prevHome = process.env.HOME;
    // Keep HOME short so broker-<uuidv7>.sock stays well under Linux UNIX_PATH_MAX (107B).
    isolatedRoot = mkdtempSync(join(tmpdir(), "op-"));
    process.env.HOME = isolatedRoot;
    vi.resetModules();
    const mod = await import("./local_mesh_commands.js");
    LocalMeshCommandsCtor = mod.LocalMeshCommands;
  });

  afterEach(async () => {
    while (cleanups.length > 0) {
      await cleanups.pop()!();
    }
  });

  afterAll(() => {
    if (prevHome === undefined) delete process.env.HOME;
    else process.env.HOME = prevHome;
    rmSync(isolatedRoot, { recursive: true, force: true });
  });

  test("concurrent root() and join() share one in-flight MeshNode without #2 follower orphaning leader", async () => {
    const cwd = createProjectCwd("solo");
    const h = makeHarness(cwd);
    cleanups.push(async () => {
      await h.commands.stop(h.ctx);
      h.commands.releaseCwdLock();
    });

    // Mirrors session_start background root() racing an explicit /outpost-pi or
    // e2e harness connect() before the first peer.connect() resolves.
    await Promise.all([
      h.commands.root(h.ctx),
      h.commands.join(h.ctx),
      h.commands.join(h.ctx),
    ]);

    const mesh = h.getNode();
    expect(mesh).not.toBeNull();
    expect(mesh!.currentRole()).toBe("leader");
    expect(mesh!.name()).toBe("solo");
    expect(mesh!.name()).not.toContain("#2");
    expect(h.setMeshNodeCalls.filter((n) => n !== null)).toHaveLength(1);
    expect(h.getAttachBridgeCalls()).toBe(1);

    // Local broker must contain exactly one registered peer (no orphaned ghost).
    const reply = await mesh!.request("broker", { type: "list_peers" }, 2_000);
    const body = reply.body as { peers?: string[] };
    expect(body.peers).toHaveLength(1);
  });

  test("stop() racing an in-flight join() fences and closes the newly connected MeshNode", async () => {
    const cwd = createProjectCwd("stopper");
    const h = makeHarness(cwd);
    cleanups.push(async () => {
      await h.commands.stop(h.ctx);
      h.commands.releaseCwdLock();
    });

    const joining = h.commands.join(h.ctx);
    await h.commands.stop(h.ctx);
    await joining;

    expect(h.getNode()).toBeNull();
    expect(h.setMeshNodeCalls.filter((n) => n !== null)).toHaveLength(0);
  });
});
