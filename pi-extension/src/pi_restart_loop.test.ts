import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { EXIT_FRESH_SESSION } from "./daemon/rpc_child.js";

const restartLoop = fileURLToPath(new URL("../../scripts/pi-restart-loop.sh", import.meta.url));

interface RestartHarness {
  capture: string;
  remoteDir: string;
}

function runRestartHarness(
  behavior: string,
  verify: (harness: RestartHarness) => void,
  setup: (harness: RestartHarness) => void = () => undefined,
  wrapperArgs: string[] = [],
  envExtra: Record<string, string> = {},
): void {
  const home = mkdtempSync(join(tmpdir(), "outpost-pi-restart-loop-"));
  try {
    const binDir = join(home, "bin");
    const remoteDir = join(home, "remote");
    const cwd = join(home, "cwd");
    const capture = join(home, "launches.txt");
    const counter = join(home, "counter.txt");
    mkdirSync(binDir);
    mkdirSync(remoteDir, { mode: 0o700 });
    mkdirSync(cwd);
    setup({ capture, remoteDir });

    const fakePi = join(binDir, "pi");
    writeFileSync(fakePi, `#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "$COUNTER" ]; then count=$(<"$COUNTER"); fi
count=$((count + 1))
printf '%s' "$count" > "$COUNTER"
printf '%s|%s\\n' "\${OUTPOST_PI_UNDER_RESTART_WRAPPER:-}" "$*" >> "$CAPTURE"
${behavior}
`);
    chmodSync(fakePi, 0o755);

    execFileSync("bash", [restartLoop, cwd, ...wrapperArgs, "--model", "test-model"], {
      env: {
        ...process.env,
        ...envExtra,
        HOME: home,
        PATH: `${binDir}:${process.env.PATH ?? ""}`,
        OUTPOST_PI_HOME: remoteDir,
        CAPTURE: capture,
        COUNTER: counter,
      },
      encoding: "utf8",
      timeout: 10_000,
    });

    verify({ capture, remoteDir });
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
}

function launches(capture: string): string[] {
  return readFileSync(capture, "utf8").trim().split("\n");
}

/** The single persistent per-folder lifecycle log the wrapper must leave
 *  behind (roomId-keyed, matching the cwd lock identity). */
function lifecycleLog(remoteDir: string): string {
  const logsDir = join(remoteDir, "logs");
  const candidates = readdirSync(logsDir).filter(
    (name) => /^pi-restart-loop-[A-Za-z0-9_-]{12}\.log$/.test(name),
  );
  if (candidates.length !== 1) {
    throw new Error(`expected exactly one lifecycle log, found: ${candidates.join(", ")}`);
  }
  return readFileSync(join(logsDir, candidates[0]!), "utf8");
}

function writeMarker(path: string): void {
  writeFileSync(path, "", { mode: 0o600 });
}

describe.skipIf(process.platform === "win32")("pi-restart-loop handshakes", () => {
  test("exit 42 launches fresh once, exports the safety gate, then hot reload resumes with --continue", () => {
    runRestartHarness(
      `case "$count" in
  1) exit ${EXIT_FRESH_SESSION} ;;
  2) (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-$$"); exit 0 ;;
  *) exit 0 ;;
esac`,
      ({ capture }) => {
        expect(launches(capture)).toEqual([
          "1|--continue --model test-model",
          "1|--model test-model",
          "1|--continue --model test-model",
        ]);
      },
    );
  }, 15_000);

  test("a stale foreign-PID marker does not authorize relaunch and remains untouched", () => {
    const foreignPid = process.pid;
    runRestartHarness(
      "exit 0",
      ({ capture, remoteDir }) => {
        expect(launches(capture)).toEqual(["1|--continue --model test-model"]);
        expect(existsSync(join(remoteDir, `.restart-marker-${foreignPid}`))).toBe(true);
      },
      ({ remoteDir }) => { writeMarker(join(remoteDir, `.restart-marker-${foreignPid}`)); },
    );
  });

  test("a refresh-dist marker relaunches under the default umask while a foreign marker remains", () => {
    const foreignPid = process.pid;
    runRestartHarness(
      `if [ "$count" -eq 1 ]; then
  umask 022
  python3 -c 'import os, sys; fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600); os.fchmod(fd, 0o600); os.close(fd)' "$OUTPOST_PI_HOME/.restart-marker-$$"
  (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-${foreignPid}")
fi
exit 0`,
      ({ capture, remoteDir }) => {
        expect(launches(capture)).toEqual([
          "1|--continue --model test-model",
          "1|--continue --model test-model",
        ]);
        expect(readdirSync(remoteDir).filter((name) => name.startsWith(".restart-marker-")))
          .toEqual([`.restart-marker-${foreignPid}`]);
      },
    );
  });

  test("a graceful exit without a marker stops after one launch", () => {
    runRestartHarness("exit 0", ({ capture }) => {
      expect(launches(capture)).toEqual(["1|--continue --model test-model"]);
    });
  });

  test("a group-readable matching marker is rejected and left untouched", () => {
    runRestartHarness(
      `: > "$OUTPOST_PI_HOME/.restart-marker-$$"
chmod 640 "$OUTPOST_PI_HOME/.restart-marker-$$"
exit 0`,
      ({ capture, remoteDir }) => {
        expect(launches(capture)).toEqual(["1|--continue --model test-model"]);
        expect(readdirSync(remoteDir).filter((name) => name.startsWith(".restart-marker-")))
          .toHaveLength(1);
      },
    );
  });

  test("--fresh-first launches the first iteration without --continue, then resumes it", () => {
    runRestartHarness(
      `if [ "$count" -eq 1 ]; then
  (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-$$"); exit 0
fi
exit 0`,
      ({ capture }) => {
        expect(launches(capture)).toEqual([
          "1|--model test-model",
          "1|--continue --model test-model",
        ]);
      },
      () => undefined,
      ["--fresh-first"],
    );
  }, 15_000);

  test("PI_RESTART_FRESH=1 (env form) drops --continue on the first iteration only", () => {
    runRestartHarness(
      `if [ "$count" -eq 1 ]; then
  (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-$$"); exit 0
fi
exit 0`,
      ({ capture }) => {
        expect(launches(capture)).toEqual([
          "1|--model test-model",
          "1|--continue --model test-model",
        ]);
      },
      () => undefined,
      [],
      { PI_RESTART_FRESH: "1" },
    );
  }, 15_000);

  test("lifecycle events persist to the per-folder log with a stop reason", () => {
    runRestartHarness("exit 0", ({ capture, remoteDir }) => {
      expect(launches(capture)).toEqual(["1|--continue --model test-model"]);
      const logText = lifecycleLog(remoteDir);
      expect(logText).toContain("cwd=");
      expect(logText).toContain("fresh-first=0");
      expect(logText).toContain("pi pid=");
      expect(logText).toContain("exited with code 0");
      expect(logText).toContain("stopping loop");
      // Every line is timestamped (UTC ISO).
      for (const line of logText.trim().split("\n")) {
        expect(line).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z /);
      }
    });
  });

  test("a fast-dying marker-authorized relaunch records RELAUNCH-FAILED-FAST", () => {
    runRestartHarness(
      `if [ "$count" -eq 1 ]; then
  (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-$$"); exit 0
fi
exit 7`,
      ({ capture, remoteDir }) => {
        expect(launches(capture)).toEqual([
          "1|--continue --model test-model",
          "1|--continue --model test-model",
        ]);
        const logText = lifecycleLog(remoteDir);
        expect(logText).toContain("RELAUNCH-FAILED-FAST");
        expect(logText).toContain("exit 7");
        expect(logText).toContain("crash safety");
      },
    );
  }, 15_000);
});
