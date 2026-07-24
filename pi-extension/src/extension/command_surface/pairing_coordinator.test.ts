import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { PairingCoordinator } from "./pairing_coordinator.js";

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

  buildContext(): unknown[] {
    return this.customMessages.map((message) => ({
      role: "custom",
      content: message.content,
    }));
  }
}

describe("PairingCoordinator.showPairQr", () => {
  const originalPairCodeFile = process.env["OUTPOST_PI_PAIR_CODE_FILE"];

  afterEach(() => {
    if (originalPairCodeFile === undefined) delete process.env["OUTPOST_PI_PAIR_CODE_FILE"];
    else process.env["OUTPOST_PI_PAIR_CODE_FILE"] = originalPairCodeFile;
    vi.restoreAllMocks();
  });

  test("keeps the rendered pairing token out of custom messages and assembled model context", async () => {
    const session = new FakeSession();
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
      // If pairing regresses to sendMessage, this fake records the exact
      // custom message that the SDK would assemble into model context.
      sendPiMessage: (message) => {
        session.sendMessage(message);
        return true;
      },
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

    const sessionCustomMessages = JSON.stringify(session.customMessages);
    const assembledModelContext = JSON.stringify(session.buildContext());
    expect(sessionCustomMessages).not.toContain(uri!);
    expect(sessionCustomMessages).not.toContain(token!);
    expect(assembledModelContext).not.toContain(uri!);
    expect(assembledModelContext).not.toContain(token!);
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
});
