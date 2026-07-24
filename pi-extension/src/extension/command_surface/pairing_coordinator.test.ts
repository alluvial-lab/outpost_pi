import { describe, expect, test, vi } from "vitest";
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
});
