import { describe, expect, test } from "vitest";
import { existsSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { MESH_WAKE_FLAG, buildClaudeLaunchArgs, removeEphemeralMcpDir, splitClaudeCliArgs, writeEphemeralMcpConfig } from "./standalone_cli.js";

describe("splitClaudeCliArgs", () => {
  test("no args → caller cwd, empty passthrough, wake off", () => {
    const res = splitClaudeCliArgs([]);
    expect(res.targetCwd).toBe(process.cwd());
    expect(res.passthroughArgs).toEqual([]);
    expect(res.meshWake).toBe(false);
  });

  test("leading positional is the cwd; the rest passes through verbatim", () => {
    const res = splitClaudeCliArgs(["/tmp/project", "--resume"]);
    expect(res.targetCwd).toBe("/tmp/project");
    expect(res.passthroughArgs).toEqual(["--resume"]);
    expect(res.meshWake).toBe(false);
  });

  test("a flag first means no cwd — flag values are not mistaken for one", () => {
    // `--resume <id>`: the id must stay in the passthrough, not become the cwd.
    const res = splitClaudeCliArgs(["--resume", "abc-123"]);
    expect(res.targetCwd).toBe(process.cwd());
    expect(res.passthroughArgs).toEqual(["--resume", "abc-123"]);
  });

  test("wake flag before the cwd does not shadow it (cwd-detection regression)", () => {
    // The wake flag must be filtered BEFORE cwd detection: otherwise the cwd
    // falls back to the invoking directory and the intended cwd is forwarded
    // to claude as a prompt positional.
    const res = splitClaudeCliArgs([MESH_WAKE_FLAG, "/tmp/proj"]);
    expect(res.targetCwd).toBe("/tmp/proj");
    expect(res.passthroughArgs).toEqual([]);
    expect(res.meshWake).toBe(true);
  });

  test("wake flag after the cwd is intercepted too", () => {
    const res = splitClaudeCliArgs(["/tmp/proj", MESH_WAKE_FLAG, "--resume"]);
    expect(res.targetCwd).toBe("/tmp/proj");
    expect(res.passthroughArgs).toEqual(["--resume"]);
    expect(res.meshWake).toBe(true);
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

  test("never injects --dangerously-skip-permissions (authority guard, absolute)", () => {
    // Auto-approving tool calls is the operator's verbatim-passthrough opt-in
    // alone — in every configuration, including wake enabled.
    for (const flags of [
      buildClaudeLaunchArgs("/tmp/mcp.json", "/pkg/skills/agent-network/SKILL.md"),
      buildClaudeLaunchArgs("/tmp/mcp.json", null),
      buildClaudeLaunchArgs("/tmp/mcp.json", null, true, ["--resume", "x"]),
    ]) {
      for (const flag of flags) {
        expect(flag).not.toContain("--dangerously-skip-permissions");
      }
    }
  });

  test("wake off (default) injects no dangerous flags at all", () => {
    // Initiative stays with the operator: without the explicit wake opt-in
    // the wrapper adds no --dangerously-* or permission-affecting flag.
    for (const flag of buildClaudeLaunchArgs("/tmp/mcp.json", null)) {
      expect(flag.startsWith("--dangerously")).toBe(false);
      expect(flag.startsWith("--allowedTools")).toBe(false);
    }
  });

  test("wake on expands dev-channels (=form) plus the read-only drain pre-approval", () => {
    expect(buildClaudeLaunchArgs("/tmp/mcp.json", null, true)).toEqual([
      "--mcp-config", "/tmp/mcp.json",
      "--dangerously-load-development-channels=server:outpost-pi-mesh",
      "--allowedTools=mcp__outpost-pi-mesh__get_messages",
    ]);
  });

  test("operator-passed dev-channels flag suppresses only the channel expansion", () => {
    // The operator supplied their own channel flag AND asked for wake via the
    // toggle: their channel flag stands, but the drain pre-approval must
    // still be generated — without it an approval-gated session wakes and
    // then stalls on the get_messages dialog nobody answers.
    for (const passthrough of [
      ["--dangerously-load-development-channels", "server:outpost-pi-mesh"],  // space form
      ["--dangerously-load-development-channels=server:outpost-pi-mesh"],     // = form
    ]) {
      const flags = buildClaudeLaunchArgs("/tmp/mcp.json", null, true, passthrough);
      expect(flags).toEqual([
        "--mcp-config", "/tmp/mcp.json",
        "--allowedTools=mcp__outpost-pi-mesh__get_messages",
      ]);
    }
  });
});

describe("writeEphemeralMcpConfig (gate-security-mcp-tmp-config-path)", () => {
  test("creates an unpredictable owner-only dir with an exclusive config inside", () => {
    const configPath = writeEphemeralMcpConfig("/fake/mesh_server.js");
    try {
      const dirMode = statSync(dirname(configPath)).mode & 0o777;
      expect(dirMode).toBe(0o700); // owner-only: no pre-positioning by other local users
      expect(existsSync(configPath)).toBe(true);
      // Exclusive-create contract: a second write into the same path must fail.
      expect(() => writeFileSync(configPath, "{}", { flag: "wx" })).toThrow();
    } finally {
      removeEphemeralMcpDir(configPath);
      expect(existsSync(configPath)).toBe(false);
    }
  });
});
