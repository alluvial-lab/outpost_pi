import { describe, expect, it, beforeEach } from "vitest";
import { SubagentGate, SUBAGENT_TOOL_NAME } from "./subagent_gate.js";

describe("SubagentGate", () => {
  let gate: SubagentGate;

  beforeEach(() => {
    gate = new SubagentGate();
  });

  describe("isActive", () => {
    it("is inactive by default", () => {
      expect(gate.isActive()).toBe(false);
    });

    it("is active after entering a subagent tool execution", () => {
      gate.enter(SUBAGENT_TOOL_NAME);
      expect(gate.isActive()).toBe(true);
    });

    it("is inactive again after the matching exit", () => {
      gate.enter(SUBAGENT_TOOL_NAME);
      gate.exit(SUBAGENT_TOOL_NAME);
      expect(gate.isActive()).toBe(false);
    });
  });

  describe("non-subagent tools", () => {
    it("enter/exit for other tool names is a no-op", () => {
      gate.enter("bash");
      expect(gate.isActive()).toBe(false);
      gate.exit("bash");
      expect(gate.isActive()).toBe(false);
    });

    it("a non-subagent tool running between subagent start/end does not close the gate", () => {
      gate.enter(SUBAGENT_TOOL_NAME);
      gate.enter("read");
      gate.exit("read");
      expect(gate.isActive()).toBe(true); // subagent still open
      gate.exit(SUBAGENT_TOOL_NAME);
      expect(gate.isActive()).toBe(false);
    });
  });

  describe("nested subagents", () => {
    it("stays active until the outermost subagent closes", () => {
      gate.enter(SUBAGENT_TOOL_NAME); // outer
      gate.enter(SUBAGENT_TOOL_NAME); // inner
      expect(gate.isActive()).toBe(true);
      gate.exit(SUBAGENT_TOOL_NAME); // inner closes
      expect(gate.isActive()).toBe(true); // outer still open
      gate.exit(SUBAGENT_TOOL_NAME); // outer closes
      expect(gate.isActive()).toBe(false);
    });
  });

  describe("floor at 0", () => {
    it("a stray exit without a matching start does not go negative", () => {
      gate.exit(SUBAGENT_TOOL_NAME); // no prior enter
      expect(gate.isActive()).toBe(false);
      // A subsequent real enter must still activate (proves depth >= 0, not < 0)
      gate.enter(SUBAGENT_TOOL_NAME);
      expect(gate.isActive()).toBe(true);
    });

    it("more exits than starts never re-enables a real open subagent prematurely", () => {
      gate.enter(SUBAGENT_TOOL_NAME); // depth 1
      gate.exit(SUBAGENT_TOOL_NAME); // depth 0
      gate.exit(SUBAGENT_TOOL_NAME); // floor at 0, not -1
      gate.enter(SUBAGENT_TOOL_NAME); // depth 1 again
      expect(gate.isActive()).toBe(true);
    });
  });

  describe("reset", () => {
    it("clears an open subagent (e.g. on session replacement)", () => {
      gate.enter(SUBAGENT_TOOL_NAME);
      gate.enter(SUBAGENT_TOOL_NAME);
      expect(gate.isActive()).toBe(true);
      gate.reset();
      expect(gate.isActive()).toBe(false);
    });
  });
});
