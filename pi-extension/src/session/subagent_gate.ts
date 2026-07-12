/**
 * `subagent_gate.ts` — suppress subagent-origin assistant messages from the
 * live broadcast + transcript replay.
 *
 * The `subagent` tool (`@gotgenes/pi-subagents`, `name: "subagent"`) runs
 * in-process and creates a child `AgentSession` that **re-binds the parent's
 * extensions** (see `@gotgenes/pi-subagents/src/lifecycle/create-subagent-
 * session.ts:177,233`). So the child session's `message_end` fires with our
 * `outpost-pi` extension bound to it, broadcasting the subagent's assistant
 * text to the phone as `agent_message` — a correct-session, wrong-content
 * leak. The SDK exposes no parent/child or subagent marker on `MessageEndEvent`
 * / `AssistantMessage` / `ctx`, so the extension cannot filter on metadata.
 *
 * Confirmed fix (live capture, 2026-07-07): the subagent's `assistant`
 * `message_end` fires **between** the parent's
 * `tool_execution_start("subagent")` and `tool_execution_end("subagent")`.
 * So a depth counter keyed on the tool name gates the leak model-independently
 * (works for same-model subagents too). See
 * `story-extension-suppress-subagent-assistant-broadcast`.
 *
 * Fork-local tradeoff: keys on the literal `SUBAGENT_TOOL_NAME` from
 * `@gotgenes/pi-subagents`. A different subagent tool/package with a different
 * `toolName` would not be caught — acceptable for the fork's single known
 * subagent provider; revisit if a second provider is adopted.
 */

/** The tool name `@gotgenes/pi-subagents` registers (`agent-tool.ts:132`). */
export const SUBAGENT_TOOL_NAME = "subagent" as const;

/**
 * Depth counter for nested subagent dispatches. Incremented on
 * `tool_execution_start` for `SUBAGENT_TOOL_NAME`, decremented on the matching
 * `tool_execution_end`. A plain number would suffice for non-nested cases,
 * but a class keeps the floor-at-0 invariant and is trivially testable.
 */
export class SubagentGate {
  private _depth = 0;

  /** Call from `tool_execution_start` with `event.toolName`. */
  enter(toolName: string): void {
    if (toolName === SUBAGENT_TOOL_NAME) this._depth += 1;
  }

  /**
   * Call from `tool_execution_end` with `event.toolName`. Floors at 0 so a
   * stray `end` without a matching `start` cannot drive the counter negative
   * and re-enable a still-open outer subagent prematurely.
   */
  exit(toolName: string): void {
    if (toolName === SUBAGENT_TOOL_NAME) this._depth = Math.max(0, this._depth - 1);
  }

  /** True while one or more subagent dispatches are open. */
  isActive(): boolean {
    return this._depth > 0;
  }

  /** Reset to 0 (e.g. on session replacement, to clear stale state). */
  reset(): void {
    this._depth = 0;
  }
}

/**
 * Process singleton shared by the `tool_execution_start` / `tool_execution_end`
 * / `message_end` handlers in `index.ts`. Module-level so it survives across
 * turns within a process; `reset()` if a session-replacement hook ever needs
 * to clear it (currently the counter self-corrects on `tool_execution_end`,
 * so no reset is wired).
 */
export const subagentGate = new SubagentGate();
