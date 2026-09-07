import { execFile } from "node:child_process";
import type { ContextUsage } from "@earendil-works/pi-coding-agent";

/** Room metadata telemetry fields owned by the session sampler. */
export type SessionTelemetryPatch = {
  branch?: string | null;
  ctx_percent?: number | null;
  ctx_max?: number | null;
};

/** Read fresh context usage from the active Pi session. */
export type ContextUsageSource = () => ContextUsage | undefined;

/** Resolve the active session cwd, or undefined before session binding. */
export type CwdSource = () => string | undefined;

/** Run the branch lookup without exposing shell interpolation to the cwd. */
export function runGitBranch(cwd: string, timeoutMs: number): Promise<string | null> {
  return new Promise((resolve) => {
    execFile(
      "git",
      ["branch", "--show-current"],
      { cwd, timeout: timeoutMs, encoding: "utf8", maxBuffer: 4096 },
      (error, stdout) => {
        if (error || typeof stdout !== "string") {
          resolve(null);
          return;
        }
        const branch = stdout.trim();
        resolve(branch.length > 0 ? branch : null);
      },
    );
  });
}

type PublishedState = {
  branch: string | null | undefined;
  ctxPercent: number | null | undefined;
  ctxMax: number | null | undefined;
};

/**
 * Sample session context at lifecycle boundaries and publish only changed room
 * metadata. Context usage is synchronous; branch lookup is asynchronous and is
 * coalesced while one lookup is in flight.
 */
export class SessionTelemetryPublisher {
  private readonly gitTimeoutMs: number;
  private published: PublishedState = {
    branch: undefined,
    ctxPercent: undefined,
    ctxMax: undefined,
  };
  private branchInFlight: Promise<void> | null = null;
  private generation = 0;

  constructor(private readonly opts: {
    publish: (patch: SessionTelemetryPatch) => void;
    usage: ContextUsageSource;
    cwd: CwdSource;
    runGitBranch: (cwd: string, timeoutMs: number) => Promise<string | null>;
    gitTimeoutMs?: number;
  }) {
    this.gitTimeoutMs = opts.gitTimeoutMs ?? 2_000;
  }

  /** Sample all available telemetry at a session boundary. */
  onSessionStart(): void {
    this.reset();
    this.sampleWithBranch();
  }

  /** Sample context usage when a low-level agent run starts. */
  onAgentStart(): void {
    this.publishUsage(this.readUsage());
  }

  /** Sample context and branch after retries and queued work have settled. */
  onAgentSettled(): void {
    this.sampleWithBranch();
  }

  /** Sample the post-compaction usage state, including meaningful null clears. */
  onSessionCompact(): void {
    this.publishUsage(this.readUsage());
  }

  /** Forget state at a session boundary and invalidate older async lookups. */
  reset(): void {
    this.generation += 1;
    this.published = { branch: undefined, ctxPercent: undefined, ctxMax: undefined };
    this.branchInFlight = null;
  }

  /** Expose normalized state for focused unit tests. */
  stateForTest(): { branch: string | null; ctxPercent: number | null; ctxMax: number | null } {
    return {
      branch: this.published.branch ?? null,
      ctxPercent: this.published.ctxPercent ?? null,
      ctxMax: this.published.ctxMax ?? null,
    };
  }

  /** Return known values for inclusion in the next hello room metadata. */
  patchForHello(): SessionTelemetryPatch {
    return {
      ...(this.published.branch !== undefined ? { branch: this.published.branch } : {}),
      ...(this.published.ctxPercent !== undefined ? { ctx_percent: this.published.ctxPercent } : {}),
      ...(this.published.ctxMax !== undefined ? { ctx_max: this.published.ctxMax } : {}),
    };
  }

  private readUsage(): { ctxPercent: number | null; ctxMax: number | null } | null {
    let usage: ContextUsage | undefined;
    try {
      usage = this.opts.usage();
    } catch {
      return null;
    }
    if (!usage) return null;
    const percent = usage.percent === null || !Number.isFinite(usage.percent)
      ? null
      : Math.max(0, Math.min(100, Math.round(usage.percent)));
    const max = Number.isFinite(usage.contextWindow) && usage.contextWindow >= 0
      ? Math.round(usage.contextWindow)
      : null;
    return { ctxPercent: percent, ctxMax: max };
  }

  private publishUsage(usage: { ctxPercent: number | null; ctxMax: number | null } | null): void {
    if (!usage) return;
    this.publishChanged({
      ctx_percent: usage.ctxPercent,
      ctx_max: usage.ctxMax,
    });
  }

  private sampleWithBranch(): void {
    const usage = this.readUsage();
    const cwd = this.readCwd();
    const generation = this.generation;
    if (!cwd) {
      this.publishUsage(usage);
      return;
    }
    if (this.branchInFlight) return;
    const lookup = Promise.resolve()
      .then(() => this.opts.runGitBranch(cwd, this.gitTimeoutMs))
      .catch(() => null)
      .then((branch) => {
        if (generation !== this.generation) return;
        this.publishChanged({
          ...(usage ? { ctx_percent: usage.ctxPercent, ctx_max: usage.ctxMax } : {}),
          branch,
        });
      })
      .finally(() => {
        if (generation === this.generation) this.branchInFlight = null;
      });
    this.branchInFlight = lookup;
  }

  private readCwd(): string | undefined {
    try {
      const cwd = this.opts.cwd();
      return typeof cwd === "string" && cwd.length > 0 ? cwd : undefined;
    } catch {
      return undefined;
    }
  }

  private publishChanged(candidate: SessionTelemetryPatch): void {
    const patch: SessionTelemetryPatch = {};
    if (Object.hasOwn(candidate, "branch") && candidate.branch !== this.published.branch) {
      patch.branch = candidate.branch;
      this.published.branch = candidate.branch;
    }
    if (Object.hasOwn(candidate, "ctx_percent") && candidate.ctx_percent !== this.published.ctxPercent) {
      patch.ctx_percent = candidate.ctx_percent;
      this.published.ctxPercent = candidate.ctx_percent;
    }
    if (Object.hasOwn(candidate, "ctx_max") && candidate.ctx_max !== this.published.ctxMax) {
      patch.ctx_max = candidate.ctx_max;
      this.published.ctxMax = candidate.ctx_max;
    }
    if (Object.keys(patch).length > 0) this.opts.publish(patch);
  }
}
