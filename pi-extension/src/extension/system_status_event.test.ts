import { describe, expect, test, vi } from "vitest";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { emitSystemStatusEvent } from "./system_status_event.js";

describe("system status event boundary", () => {
  test("display:false custom messages still enter the SDK model context", () => {
    const session = SessionManager.inMemory("/tmp/outpost-pi-status-diagnosis");
    session.appendCustomMessageEntry(
      "outpost-pi:name-assigned",
      "Mesh name: outpost_pi",
      false,
      { assigned: "outpost_pi" },
    );
    session.appendCustomMessageEntry(
      "outpost-pi:relay-state",
      "Relay connected",
      false,
      { status: "connected", connected: true },
    );

    expect(session.getEntries().map((entry) => entry.type)).toEqual([
      "custom_message",
      "custom_message",
    ]);
    expect(session.buildSessionContext().messages).toEqual([
      expect.objectContaining({ role: "custom", content: "Mesh name: outpost_pi", display: false }),
      expect.objectContaining({ role: "custom", content: "Relay connected", display: false }),
    ]);
  });

  test("RPC status emission notifies the client without enqueueing session context", () => {
    const session = SessionManager.inMemory("/tmp/outpost-pi-status-regression");
    const notify = vi.fn();

    expect(emitSystemStatusEvent(
      { mode: "rpc", ui: { notify } },
      {
        customType: "outpost-pi:name-assigned",
        details: { requested: "outpost_pi", assigned: "outpost_pi", changed: false },
      },
    )).toBe(true);

    expect(notify).toHaveBeenCalledWith(
      JSON.stringify({
        customType: "outpost-pi:name-assigned",
        details: { requested: "outpost_pi", assigned: "outpost_pi", changed: false },
      }),
      "info",
    );
    expect(session.getEntries()).toEqual([]);
    expect(session.buildSessionContext().messages).toEqual([]);
  });

  test("non-RPC modes leave structured status to their existing UI chrome", () => {
    const notify = vi.fn();

    expect(emitSystemStatusEvent(
      { mode: "tui", ui: { notify } },
      { customType: "outpost-pi:relay-state", details: { status: "connected", connected: true } },
    )).toBe(false);

    expect(notify).not.toHaveBeenCalled();
  });
});
