import { describe, expect, test } from "vitest";
import { buildClaudeLaunchArgs, splitClaudeCliArgs } from "./standalone_cli.js";

describe("splitClaudeCliArgs", () => {
  test("no args → caller cwd, empty passthrough", () => {
    const res = splitClaudeCliArgs([]);
    expect(res.targetCwd).toBe(process.cwd());
    expect(res.passthroughArgs).toEqual([]);
  });

  test("leading positional is the cwd; the rest passes through verbatim", () => {
    const res = splitClaudeCliArgs(["/tmp/project", "--resume"]);
    expect(res.targetCwd).toBe("/tmp/project");
    expect(res.passthroughArgs).toEqual(["--resume"]);
  });

  test("a flag first means no cwd — flag values are not mistaken for one", () => {
    // `--resume <id>`: the id must stay in the passthrough, not become the cwd.
    const res = splitClaudeCliArgs(["--resume", "abc-123"]);
    expect(res.targetCwd).toBe(process.cwd());
    expect(res.passthroughArgs).toEqual(["--resume", "abc-123"]);
  });

  test("returns a copy — callers cannot mutate the input argv", () => {
    const input = ["--resume"];
    const res = splitClaudeCliArgs(input);
    res.passthroughArgs.push("--extra");
    expect(input).toEqual(["--resume"]);
  });
});

describe("buildClaudeLaunchArgs", () => {
  test("wires the ephemeral MCP config and the packaged skill append", () => {
    expect(buildClaudeLaunchArgs("/tmp/mcp.json", "/pkg/skills/agent-network/SKILL.md")).toEqual([
      "--mcp-config", "/tmp/mcp.json",
      "--append-system-prompt-file=/pkg/skills/agent-network/SKILL.md",
    ]);
  });

  test("skill append is omitted when the packaged skill is missing", () => {
    expect(buildClaudeLaunchArgs("/tmp/mcp.json", null)).toEqual([
      "--mcp-config", "/tmp/mcp.json",
    ]);
  });

  test("never injects a --dangerously-* flag (safe-default regression guard)", () => {
    // Permission bypass and development channels are operator opt-ins passed
    // through as trailing claude-flags — the wrapper must not add them itself.
    for (const flags of [
      buildClaudeLaunchArgs("/tmp/mcp.json", "/pkg/skills/agent-network/SKILL.md"),
      buildClaudeLaunchArgs("/tmp/mcp.json", null),
    ]) {
      for (const flag of flags) {
        expect(flag.startsWith("--dangerously")).toBe(false);
      }
    }
  });
});
