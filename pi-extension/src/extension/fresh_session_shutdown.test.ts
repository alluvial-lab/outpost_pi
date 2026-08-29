import { describe, expect, test, vi } from "vitest";
import { FreshSessionShutdownCoordinator } from "./fresh_session_shutdown.js";

function deferred<T = void>(): {
  promise: Promise<T>;
  resolve(value: T): void;
} {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((accept) => { resolve = accept; });
  return { promise, resolve };
}

describe("FreshSessionShutdownCoordinator", () => {
  test("fences synchronously, drains once, and stages before runtime shutdown", async () => {
    const drain = deferred();
    const shutdown = deferred<boolean>();
    const order: string[] = [];
    const terminate = vi.fn(() => { order.push("terminate"); });
    const coordinator = new FreshSessionShutdownCoordinator({
      isRestartManaged: () => true,
      drainAcceptedDeliveries: async () => {
        order.push("drain-started");
        await drain.promise;
        order.push("drain-finished");
      },
      terminate,
      shutdownDeadlineMs: 10_000,
      exitCode: 42,
    });

    const request = coordinator.request({
      stageAcknowledgementAndReset: () => { order.push("stage"); },
      shutdownRuntime: async () => {
        order.push("shutdown-started");
        const owned = await shutdown.promise;
        order.push("shutdown-finished");
        return owned;
      },
    });

    expect(coordinator.fenceReason).toBe("fresh_session");
    await expect(coordinator.request({
      stageAcknowledgementAndReset: vi.fn(),
      shutdownRuntime: vi.fn(),
    })).resolves.toEqual({ status: "already_quiescing" });
    expect(order).toEqual(["drain-started"]);

    drain.resolve();
    await vi.waitFor(() => expect(order).toContain("shutdown-started"));
    expect(order).toEqual([
      "drain-started",
      "drain-finished",
      "stage",
      "shutdown-started",
    ]);
    expect(terminate).not.toHaveBeenCalled();

    shutdown.resolve(true);
    await expect(request).resolves.toEqual({ status: "exiting", drain: "complete" });
    expect(order).toEqual([
      "drain-started",
      "drain-finished",
      "stage",
      "shutdown-started",
      "shutdown-finished",
      "terminate",
    ]);
    expect(terminate).toHaveBeenCalledOnce();
    expect(terminate).toHaveBeenCalledWith(42);
  });

  test("deadline exhaustion terminates without treating pending I/O as proof", async () => {
    vi.useFakeTimers();
    try {
      const drain = deferred();
      const terminate = vi.fn();
      const coordinator = new FreshSessionShutdownCoordinator({
        isRestartManaged: () => true,
        drainAcceptedDeliveries: () => drain.promise,
        terminate,
        shutdownDeadlineMs: 50,
        exitCode: 42,
      });
      const stage = vi.fn();
      const shutdownRuntime = vi.fn(async () => true);

      const request = coordinator.request({
        stageAcknowledgementAndReset: stage,
        shutdownRuntime,
      });
      await vi.advanceTimersByTimeAsync(50);

      await expect(request).resolves.toEqual({
        status: "exiting",
        drain: "deadline_exceeded",
      });
      expect(stage).not.toHaveBeenCalled();
      expect(shutdownRuntime).toHaveBeenCalledOnce();
      expect(shutdownRuntime).toHaveBeenCalledWith("new");
      expect(terminate).toHaveBeenCalledWith(42);
      drain.resolve();
      await vi.runAllTimersAsync();
    } finally {
      vi.useRealTimers();
    }
  });

  test("a stale runtime never exits and releases the fresh-session fence", async () => {
    const terminate = vi.fn();
    const coordinator = new FreshSessionShutdownCoordinator({
      isRestartManaged: () => true,
      drainAcceptedDeliveries: async () => undefined,
      terminate,
      shutdownDeadlineMs: 10_000,
      exitCode: 42,
    });
    const stage = vi.fn();

    await expect(coordinator.request({
      stageAcknowledgementAndReset: stage,
      shutdownRuntime: async () => false,
    })).resolves.toEqual({ status: "stale_runtime" });

    expect(stage).toHaveBeenCalledOnce();
    expect(terminate).not.toHaveBeenCalled();
    expect(coordinator.fenceReason).toBeNull();
  });

  test("bare requests reuse the fence, drain, lifecycle shutdown, and exit sequence", async () => {
    const order: string[] = [];
    const coordinator = new FreshSessionShutdownCoordinator({
      isRestartManaged: () => false,
      drainAcceptedDeliveries: async () => { order.push("drain"); },
      terminate: (exitCode) => { order.push(`exit:${exitCode}`); },
      shutdownDeadlineMs: 10_000,
      exitCode: 42,
    });

    await expect(coordinator.request({
      shutdownRuntime: async () => { order.push("shutdown"); return true; },
    }, { allowUnmanaged: true })).resolves.toEqual({
      status: "exiting",
      drain: "complete",
    });
    expect(order).toEqual(["drain", "shutdown", "exit:42"]);
    expect(coordinator.fenceReason).toBe("fresh_session");
  });

  test("unmanaged and hot-reload-owned requests do not start fresh shutdown", async () => {
    const unmanaged = new FreshSessionShutdownCoordinator({
      isRestartManaged: () => false,
      drainAcceptedDeliveries: vi.fn(),
      terminate: vi.fn(),
      shutdownDeadlineMs: 10_000,
      exitCode: 42,
    });
    await expect(unmanaged.request({
      stageAcknowledgementAndReset: vi.fn(),
      shutdownRuntime: vi.fn(),
    })).resolves.toEqual({ status: "unavailable" });
    expect(unmanaged.fenceReason).toBeNull();

    const hotReload = new FreshSessionShutdownCoordinator({
      isRestartManaged: () => true,
      drainAcceptedDeliveries: vi.fn(),
      terminate: vi.fn(),
      shutdownDeadlineMs: 10_000,
      exitCode: 42,
    });
    expect(hotReload.beginHotReloadFence()).toBe(true);
    expect(hotReload.beginHotReloadFence()).toBe(false);
    await expect(hotReload.request({
      stageAcknowledgementAndReset: vi.fn(),
      shutdownRuntime: vi.fn(),
    })).resolves.toEqual({ status: "already_quiescing" });
  });
});
