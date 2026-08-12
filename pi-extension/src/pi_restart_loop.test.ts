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

    execFileSync("bash", [restartLoop, cwd, "--model", "test-model"], {
      env: {
        ...process.env,
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

  test("an own marker relaunches while a foreign marker remains for its wrapper", () => {
    const foreignPid = process.pid;
    runRestartHarness(
      `if [ "$count" -eq 1 ]; then
  (umask 077; : > "$OUTPOST_PI_HOME/.restart-marker-$$")
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

  test("an insecure matching marker is rejected and left untouched", () => {
    runRestartHarness(
      `: > "$OUTPOST_PI_HOME/.restart-marker-$$"
chmod 644 "$OUTPOST_PI_HOME/.restart-marker-$$"
exit 0`,
      ({ capture, remoteDir }) => {
        expect(launches(capture)).toEqual(["1|--continue --model test-model"]);
        expect(readdirSync(remoteDir).filter((name) => name.startsWith(".restart-marker-")))
          .toHaveLength(1);
      },
    );
  });
});
