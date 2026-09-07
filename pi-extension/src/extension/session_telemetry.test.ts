import { describe, expect, test, vi } from "vitest";
import { SessionTelemetryPublisher } from "./session_telemetry.js";

function usage(percent: number | null, contextWindow = 100_000): { tokens: number | null; contextWindow: number; percent: number | null } {
  return { tokens: percent === null ? null : Math.round(contextWindow * percent / 100), contextWindow, percent };
}

async function settle(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
}

describe("SessionTelemetryPublisher", () => {
  test("publishes one delta patch and does not republish unchanged values", async () => {
    const publish = vi.fn();
    const runGitBranch = vi.fn().mockResolvedValue("main");
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => usage(91, 1_000_000),
      cwd: () => "/repo",
      runGitBranch,
    });

    publisher.onSessionStart();
    await settle();
    expect(publish).toHaveBeenCalledTimes(1);
    expect(publish).toHaveBeenLastCalledWith({ branch: "main", ctx_percent: 91, ctx_max: 1_000_000 });

    publisher.onAgentSettled();
    await settle();
    expect(publish).toHaveBeenCalledTimes(1);
    expect(runGitBranch).toHaveBeenCalledTimes(2);
  });

  test("publishes usage-only deltas at agent start", () => {
    const publish = vi.fn();
    let current = usage(20);
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => current,
      cwd: () => "/repo",
      runGitBranch: vi.fn().mockResolvedValue("main"),
    });

    publisher.onAgentStart();
    expect(publish).toHaveBeenCalledWith({ ctx_percent: 20, ctx_max: 100_000 });
    current = usage(22);
    publisher.onAgentStart();
    expect(publish).toHaveBeenLastCalledWith({ ctx_percent: 22 });
  });

  test("clears a stale percent after compaction without republishing max", () => {
    const publish = vi.fn();
    let current = usage(90);
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => current,
      cwd: () => "/repo",
      runGitBranch: vi.fn().mockResolvedValue("main"),
    });

    publisher.onAgentStart();
    current = usage(null);
    publisher.onSessionCompact();
    expect(publish).toHaveBeenLastCalledWith({ ctx_percent: null });
    expect(publisher.stateForTest()).toEqual({ branch: null, ctxPercent: null, ctxMax: 100_000 });
  });

  test("publishes a git timeout or empty result as one null clear", async () => {
    const publish = vi.fn();
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => undefined,
      cwd: () => "/repo",
      runGitBranch: vi.fn().mockResolvedValue(null),
    });

    publisher.onSessionStart();
    await settle();
    publisher.onAgentSettled();
    await settle();
    expect(publish).toHaveBeenCalledTimes(1);
    expect(publish).toHaveBeenCalledWith({ branch: null });
  });

  test("reset forgets the last-published state", async () => {
    const publish = vi.fn();
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => usage(10),
      cwd: () => "/repo",
      runGitBranch: vi.fn().mockResolvedValue("main"),
    });

    publisher.onSessionStart();
    await settle();
    publisher.reset();
    publisher.onSessionStart();
    await settle();
    expect(publish).toHaveBeenCalledTimes(2);
    expect(publisher.stateForTest()).toEqual({ branch: "main", ctxPercent: 10, ctxMax: 100_000 });
  });

  test("re-samples usage when a delayed branch lookup completes after compaction", async () => {
    const publish = vi.fn();
    let current = usage(92);
    let resolveBranch!: (branch: string | null) => void;
    const runGitBranch = vi.fn(() => new Promise<string | null>((resolve) => {
      resolveBranch = resolve;
    }));
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => current,
      cwd: () => "/repo",
      runGitBranch,
    });

    publisher.onAgentStart();
    publisher.onAgentSettled();
    await settle();
    current = usage(null);
    publisher.onSessionCompact();
    expect(publish).toHaveBeenLastCalledWith({ ctx_percent: null });

    const callsBeforeResolve = publish.mock.calls.length;
    resolveBranch("main");
    await settle();
    expect(publish).toHaveBeenLastCalledWith({ branch: "main" });
    expect(publish.mock.calls.slice(callsBeforeResolve)).not.toContainEqual([{ ctx_percent: 92, ctx_max: 100_000 }]);
    expect(publisher.stateForTest()).toEqual({ branch: "main", ctxPercent: null, ctxMax: 100_000 });
  });

  test("publishes newer usage while an earlier settled branch lookup is in flight", async () => {
    const publish = vi.fn();
    let current = usage(20);
    let resolveBranch!: (branch: string | null) => void;
    const runGitBranch = vi.fn(() => new Promise<string | null>((resolve) => {
      resolveBranch = resolve;
    }));
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => current,
      cwd: () => "/repo",
      runGitBranch,
    });

    publisher.onAgentSettled();
    await settle();
    current = usage(22);
    publisher.onAgentSettled();
    expect(publish).toHaveBeenLastCalledWith({ ctx_percent: 22, ctx_max: 100_000 });
    expect(runGitBranch).toHaveBeenCalledTimes(1);

    resolveBranch("main");
    await settle();
    expect(publish).toHaveBeenLastCalledWith({ branch: "main" });
    expect(publisher.stateForTest()).toEqual({ branch: "main", ctxPercent: 22, ctxMax: 100_000 });
  });

  test("coalesces an in-flight branch lookup and ignores stale usage errors", async () => {
    const publish = vi.fn();
    let resolveBranch!: (branch: string | null) => void;
    const runGitBranch = vi.fn(() => new Promise<string | null>((resolve) => { resolveBranch = resolve; }));
    const publisher = new SessionTelemetryPublisher({
      publish,
      usage: () => { throw new Error("stale after session replacement or reload"); },
      cwd: () => "/repo",
      runGitBranch,
    });

    expect(() => publisher.onSessionStart()).not.toThrow();
    publisher.onAgentSettled();
    await settle();
    expect(runGitBranch).toHaveBeenCalledTimes(1);
    resolveBranch("main");
    await settle();
    expect(publish).toHaveBeenCalledWith({ branch: "main" });
  });
});
