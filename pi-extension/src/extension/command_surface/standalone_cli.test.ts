import { describe, expect, test, vi } from "vitest";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname } from "node:path";
import {
  MESH_WAKE_FLAG,
  PUSH_DELIVER_FLAG,
  buildClaudeLaunchArgs,
  launchClaudeCli,
  removeEphemeralMcpDir,
  splitClaudeCliArgs,
  validateClaudeCliArgs,
  writeEphemeralMcpConfig,
} from "./standalone_cli.js";
import { PUSH_DELIVER_ENV_VAR } from "../../mcp/push_delivery.js";

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
    expect(res.pushDeliver).toBe(false);
  });

  test("push-deliver flag is stripped before cwd detection and never leaked to passthrough", () => {
    const before = splitClaudeCliArgs([PUSH_DELIVER_FLAG, MESH_WAKE_FLAG, "/tmp/proj", "--resume"]);
    expect(before).toEqual({
      targetCwd: "/tmp/proj",
      meshWake: true,
      pushDeliver: true,
      passthroughArgs: ["--resume"],
    });

    const after = splitClaudeCliArgs(["/tmp/proj", MESH_WAKE_FLAG, PUSH_DELIVER_FLAG]);
    expect(after).toEqual({
      targetCwd: "/tmp/proj",
      meshWake: true,
      pushDeliver: true,
      passthroughArgs: [],
    });
  });
});

describe("validateClaudeCliArgs & fail-fast --push-deliver contract", () => {
  test("permits default, wake-only, and wake+push-deliver combinations", () => {
    expect(validateClaudeCliArgs({ meshWake: false, pushDeliver: false })).toBeNull();
    expect(validateClaudeCliArgs({ meshWake: true, pushDeliver: false })).toBeNull();
    expect(validateClaudeCliArgs({ meshWake: true, pushDeliver: true })).toBeNull();
  });

  test("rejects --push-deliver without --outpost-mesh-wake with actionable usage error", () => {
    const err = validateClaudeCliArgs({ meshWake: false, pushDeliver: true });
    expect(err).not.toBeNull();
    expect(err).toContain(PUSH_DELIVER_FLAG);
    expect(err).toContain(MESH_WAKE_FLAG);
  });

  test("rejects ambient OUTPOST_PI_MCP_PUSH_DELIVER=1 without --outpost-mesh-wake", () => {
    const err = validateClaudeCliArgs(
      { meshWake: false, pushDeliver: false },
      { [PUSH_DELIVER_ENV_VAR]: "1" },
    );
    expect(err).not.toBeNull();
    expect(err).toContain(PUSH_DELIVER_ENV_VAR);
    expect(err).toContain(MESH_WAKE_FLAG);
    expect(
      validateClaudeCliArgs(
        { meshWake: true, pushDeliver: false },
        { [PUSH_DELIVER_ENV_VAR]: "1" },
      ),
    ).toBeNull();
  });

  test("launchClaudeCli exits 1 fail-fast when --push-deliver or ambient OUTPOST_PI_MCP_PUSH_DELIVER=1 lacks --outpost-mesh-wake", async () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code?: string | number | null): never => {
      throw new Error(`EXIT:${String(code)}`);
    });
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const prevEnv = process.env[PUSH_DELIVER_ENV_VAR];
    try {
      delete process.env[PUSH_DELIVER_ENV_VAR];
      await expect(
        launchClaudeCli([PUSH_DELIVER_FLAG], import.meta.url),
      ).rejects.toThrow("EXIT:1");
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(MESH_WAKE_FLAG));

      errorSpy.mockClear();
      await expect(
        launchClaudeCli(
          [PUSH_DELIVER_FLAG, "--dangerously-load-development-channels=server:outpost-pi-mesh"],
          import.meta.url,
        ),
      ).rejects.toThrow("EXIT:1");
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(PUSH_DELIVER_FLAG));

      errorSpy.mockClear();
      process.env[PUSH_DELIVER_ENV_VAR] = "1";
      await expect(
        launchClaudeCli([], import.meta.url),
      ).rejects.toThrow("EXIT:1");
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(PUSH_DELIVER_ENV_VAR));
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining(MESH_WAKE_FLAG));
    } finally {
      if (prevEnv === undefined) delete process.env[PUSH_DELIVER_ENV_VAR];
      else process.env[PUSH_DELIVER_ENV_VAR] = prevEnv;
      exitSpy.mockRestore();
      errorSpy.mockRestore();
    }
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
  test("creates unpredictable owner-only dirs with the exact server config, exclusively", () => {
    const first = writeEphemeralMcpConfig("/fake/mesh_server.js");
    const second = writeEphemeralMcpConfig("/fake/mesh_server.js");
    try {
      // Unpredictable across calls: two launches never share a path another
      // local user could pre-position.
      expect(dirname(first)).not.toBe(dirname(second));
      for (const configPath of [first, second]) {
        const dirMode = statSync(dirname(configPath)).mode & 0o777;
        expect(dirMode).toBe(0o700); // owner-only
        // The execution-bearing content is exactly the wrapper's contract.
        const parsed = JSON.parse(readFileSync(configPath, "utf8")) as {
          mcpServers: Record<string, { command: string; args: string[] }>;
        };
        const server = parsed.mcpServers["outpost-pi-mesh"]!;
        expect(server.command).toBe(process.execPath);
        expect(server.args).toEqual(["/fake/mesh_server.js"]);
      }
    } finally {
      removeEphemeralMcpDir(first);
      removeEphemeralMcpDir(second);
      expect(existsSync(first)).toBe(false);
      expect(existsSync(second)).toBe(false);
    }
  });

  test("appends --push-deliver to mesh_server args only when explicitly enabled", () => {
    const offPath = writeEphemeralMcpConfig("/fake/mesh_server.js", { pushDeliver: false });
    const onPath = writeEphemeralMcpConfig("/fake/mesh_server.js", { pushDeliver: true });
    try {
      const readArgs = (p: string) =>
        (JSON.parse(readFileSync(p, "utf8")) as { mcpServers: Record<string, { args: string[] }> })
          .mcpServers["outpost-pi-mesh"]!.args;
      expect(readArgs(offPath)).toEqual(["/fake/mesh_server.js"]);
      expect(readArgs(onPath)).toEqual(["/fake/mesh_server.js", PUSH_DELIVER_FLAG]);
    } finally {
      removeEphemeralMcpDir(offPath);
      removeEphemeralMcpDir(onPath);
    }
  });
});
