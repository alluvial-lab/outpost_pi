import { chmod, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { qrSession } from "../../pairing/qr.js";
import { PairingCoordinator } from "./pairing_coordinator.js";
import type { SelfRevokeOptions } from "../../mesh/self_revoke.js";

type CustomMessage = Parameters<ExtensionAPI["sendMessage"]>[0];
type PairingDialogFactory = (
  tui: never,
  theme: never,
  keybindings: never,
  done: (result: void) => void,
) => { render(width: number): string[] };

class FakeSession {
  readonly customMessages: CustomMessage[] = [];

  sendMessage(message: CustomMessage): void {
    this.customMessages.push(message);
  }
}

describe("PairingCoordinator.showPairQr", () => {
  const originalPairCodeFile = process.env["OUTPOST_PI_PAIR_CODE_FILE"];

  afterEach(() => {
    if (originalPairCodeFile === undefined) delete process.env["OUTPOST_PI_PAIR_CODE_FILE"];
    else process.env["OUTPOST_PI_PAIR_CODE_FILE"] = originalPairCodeFile;
    vi.restoreAllMocks();
  });

  test("listDevices treats a stale UI capability after storage await as a safe no-op", async () => {
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room",
      displayName: () => "Test Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage: () => true,
      setSiblings: () => undefined,
    });
    const ui = { notify: vi.fn(() => { throw new Error("stale after session replacement or reload"); }) };

    await expect(coordinator.listDevices({ ui } as never)).resolves.toBeUndefined();
    expect(ui.notify).toHaveBeenCalledOnce();
  });

  test("self-revoke waits for owner detach before publishing its local notice", async () => {
    let onRevoke!: NonNullable<SelfRevokeOptions["onRevoke"]>;
    let release!: () => void;
    const detachGate = new Promise<void>((resolve) => { release = resolve; });
    const detach = vi.fn(() => detachGate);
    const sendPiMessage = vi.fn(() => true);
    const poller = { start: vi.fn(), stop: vi.fn() };
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room",
      displayName: () => "Test Pi",
      owners: { detach } as never,
      ownerHas: () => true,
      refreshPairingsCache: vi.fn(),
      joinLocalMesh: async () => undefined,
      sendPiMessage,
      setSiblings: () => undefined,
    }, (options) => {
      onRevoke = options.onRevoke!;
      return poller as never;
    });

    coordinator.startSelfRevoke("https://relay.test", {
      publicKey: new Uint8Array(32),
      secretKey: new Uint8Array(32),
    });
    const revoking = onRevoke("owner-epk");
    await Promise.resolve();

    expect(detach).toHaveBeenCalledOnce();
    expect(detach).toHaveBeenCalledWith("owner-epk", "session_replaced");
    expect(sendPiMessage).not.toHaveBeenCalled();

    release();
    await revoking;
    expect(sendPiMessage).toHaveBeenCalledOnce();
  });

  test("self-revoke detach rejection stays on the awaited callback chain", async () => {
    let onRevoke!: NonNullable<SelfRevokeOptions["onRevoke"]>;
    const detachError = new Error("detach failed");
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room",
      displayName: () => "Test Pi",
      owners: { detach: vi.fn(async () => { throw detachError; }) } as never,
      ownerHas: () => true,
      refreshPairingsCache: vi.fn(),
      joinLocalMesh: async () => undefined,
      sendPiMessage: vi.fn(() => true),
      setSiblings: () => undefined,
    }, (options) => {
      onRevoke = options.onRevoke!;
      return { start: vi.fn(), stop: vi.fn() } as never;
    });

    coordinator.startSelfRevoke("https://relay.test", {
      publicKey: new Uint8Array(32),
      secretKey: new Uint8Array(32),
    });

    await expect(onRevoke("owner-epk")).rejects.toBe(detachError);
  });

  test("renders pairing only in the TUI without sending model-context messages", async () => {
    const session = new FakeSession();
    const sendPiMessage = vi.fn((message: CustomMessage) => {
      session.sendMessage(message);
      return true;
    });
    let rendered = "";
    const custom = vi.fn(async (factory: PairingDialogFactory) => {
      const component = await factory(
        {} as never,
        {
          fg: (_color: string, text: string) => text,
          bold: (text: string) => text,
        } as never,
        {} as never,
        () => undefined,
      );
      rendered = component.render(500).join("\n");
    });
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room-under-test",
      displayName: () => "Test Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage,
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({ publicKey: new Uint8Array(32), secretKey: new Uint8Array(32) });
    const ctx = {
      cwd: "/tmp/outpost-pi-pairing-test",
      mode: "tui",
      ui: { custom, notify: vi.fn() },
    } as unknown as ExtensionContext;

    await coordinator.showPairQr(ctx);

    const uri = rendered.match(/outpostpi:\/\/pair\?\S+/)?.[0];
    expect(uri).toBeDefined();
    const token = new URL(uri!).searchParams.get("t");
    expect(token).toBeTruthy();

    expect(sendPiMessage).not.toHaveBeenCalled();
    expect(session.customMessages).toEqual([]);
  });

  test("reacquires the live session UI after asynchronous pair-code publication", async () => {
    const directory = await mkdtemp(join(tmpdir(), "outpost-pi-pair-dialog-session-"));
    process.env["OUTPOST_PI_PAIR_CODE_FILE"] = join(directory, "pair-code.json");
    const staleCustom = vi.fn(() => {
      throw new Error("stale after session replacement or reload");
    });
    const freshCustom = vi.fn(async () => undefined);
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      currentUi: () => ({ custom: freshCustom, notify: vi.fn() } as never),
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room-under-test",
      displayName: () => "Test Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage: () => true,
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({
      publicKey: new Uint8Array(32),
      secretKey: new Uint8Array(32),
    });
    const staleCtx = {
      cwd: directory,
      mode: "tui",
      ui: { custom: staleCustom, notify: vi.fn() },
    } as unknown as ExtensionContext;

    try {
      await coordinator.showPairQr(staleCtx);
      expect(freshCustom).toHaveBeenCalledOnce();
      expect(staleCustom).not.toHaveBeenCalled();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("narrow terminal still shows the copyable pairing URI when the QR won't fit", async () => {
    const session = new FakeSession();
    const sendPiMessage = vi.fn((message: CustomMessage) => {
      session.sendMessage(message);
      return true;
    });
    let renderedNarrow = "";
    const custom = vi.fn(async (factory: PairingDialogFactory) => {
      const component = await factory(
        {} as never,
        {
          fg: (_color: string, text: string) => text,
          bold: (text: string) => text,
        } as never,
        {} as never,
        () => undefined,
      );
      // Render at a width too narrow for the QR ASCII but wide enough for the
      // wrapped URI. The camera-less URI path must remain visible.
      renderedNarrow = component.render(40).join("\n");
    });
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "room-under-test",
      displayName: () => "Test Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage,
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({ publicKey: new Uint8Array(32), secretKey: new Uint8Array(32) });
    const ctx = {
      cwd: "/tmp/outpost-pi-pairing-narrow-test",
      mode: "tui",
      ui: { custom, notify: vi.fn() },
    } as unknown as ExtensionContext;

    await coordinator.showPairQr(ctx);

    // The QR is hidden, but the outpostpi:// URI is still present (wrapped
    // across lines) so a camera-less device can copy it.
    const uri = renderedNarrow.match(/outpostpi:\/\/pair\?[^\s"]+/)?.[0]
      ?? renderedNarrow.split("\n").find((line) => line.includes("outpostpi://"));
    expect(uri).toBeDefined();
    expect(renderedNarrow).not.toContain("widen to");
    expect(sendPiMessage).not.toHaveBeenCalled();
    expect(session.customMessages).toEqual([]);
  });

  test("non-TUI pairing without the seam warns without issuing or displaying a token", async () => {
    delete process.env["OUTPOST_PI_PAIR_CODE_FILE"];
    const notify = vi.fn();
    const custom = vi.fn();
    const sendPiMessage = vi.fn(() => true);
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "headless-room",
      displayName: () => "Headless Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage,
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({ publicKey: new Uint8Array(32), secretKey: new Uint8Array(32) });
    const issueToken = vi.spyOn(qrSession, "issueToken");
    const ctx = {
      cwd: "/tmp/outpost-pi-pairing-headless-test",
      mode: "rpc",
      ui: { custom, notify },
    } as unknown as ExtensionContext;

    await coordinator.showPairQr(ctx);

    expect(notify).toHaveBeenCalledWith(expect.stringMatching(/requires an interactive TUI/i), "warning");
    expect(issueToken).not.toHaveBeenCalled();
    expect(custom).not.toHaveBeenCalled();
    expect(sendPiMessage).not.toHaveBeenCalled();
  });

  test("writes the production pair code to the headless E2E seam with owner-only permissions", async () => {
    const directory = await mkdtemp(join(tmpdir(), "outpost-pi-pair-code-"));
    const pairCodeFile = join(directory, "pair-code.json");
    process.env["OUTPOST_PI_PAIR_CODE_FILE"] = pairCodeFile;
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const info = vi.spyOn(console, "info").mockImplementation(() => undefined);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const notify = vi.fn();
    const sendPiMessage = vi.fn(() => true);
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "headless-room",
      displayName: () => "Headless Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage,
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({ publicKey: new Uint8Array(32), secretKey: new Uint8Array(32) });
    const ctx = {
      cwd: "/tmp/outpost-pi-pairing-headless-test",
      mode: "rpc",
      ui: { notify },
    } as unknown as ExtensionContext;

    try {
      await coordinator.showPairQr(ctx);
      const payload = JSON.parse(await readFile(pairCodeFile, "utf8")) as Record<string, unknown>;
      const uri = payload["uri"];
      const token = payload["token"];
      expect(uri).toEqual(expect.stringMatching(/^outpostpi:\/\/pair\?/));
      expect(token).toEqual(expect.any(String));
      expect(new URL(uri as string).searchParams.get("t")).toBe(token);
      expect(payload).toMatchObject({
        roomId: "headless-room",
        name: "Headless Pi",
        expiresAt: expect.any(Number),
      });
      expect((await stat(pairCodeFile)).mode & 0o777).toBe(0o600);
      expect(sendPiMessage).not.toHaveBeenCalled();
      expect(notify).not.toHaveBeenCalled();
      expect(JSON.stringify([
        ...log.mock.calls,
        ...info.mock.calls,
        ...warn.mock.calls,
        ...error.mock.calls,
      ])).not.toContain(token as string);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("rejects a pre-existing broader-permissions pair-code target without exposing a token", async () => {
    const directory = await mkdtemp(join(tmpdir(), "outpost-pi-pair-code-existing-"));
    const pairCodeFile = join(directory, "pair-code.json");
    await writeFile(pairCodeFile, "untrusted-existing-file", "utf8");
    await chmod(pairCodeFile, 0o644);
    process.env["OUTPOST_PI_PAIR_CODE_FILE"] = pairCodeFile;
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const info = vi.spyOn(console, "info").mockImplementation(() => undefined);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const coordinator = new PairingCoordinator({
      getState: () => "started",
      startRelay: async () => undefined,
      isRelayConnected: () => true,
      roomId: () => "headless-room",
      displayName: () => "Headless Pi",
      owners: {} as never,
      ownerHas: () => false,
      refreshPairingsCache: () => undefined,
      joinLocalMesh: async () => undefined,
      sendPiMessage: vi.fn(() => true),
      setSiblings: () => undefined,
    });
    coordinator.recordCurrentKeypair({ publicKey: new Uint8Array(32), secretKey: new Uint8Array(32) });
    const ctx = {
      cwd: "/tmp/outpost-pi-pairing-headless-test",
      mode: "rpc",
      ui: { notify: vi.fn() },
    } as unknown as ExtensionContext;

    try {
      await expect(coordinator.showPairQr(ctx)).rejects.toThrow(/pair code file already exists/i);
      expect(await readFile(pairCodeFile, "utf8")).toBe("untrusted-existing-file");
      expect((await stat(pairCodeFile)).mode & 0o777).toBe(0o644);
      expect(JSON.stringify([
        ...log.mock.calls,
        ...info.mock.calls,
        ...warn.mock.calls,
        ...error.mock.calls,
      ])).not.toContain("untrusted-existing-file");
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
