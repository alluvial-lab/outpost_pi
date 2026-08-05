import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { EXIT_FRESH_SESSION } from "./daemon/rpc_child.js";

const restartLoop = fileURLToPath(new URL("../../scripts/pi-restart-loop.sh", import.meta.url));

describe("pi-restart-loop fresh-session handshake", () => {
  test.skipIf(process.platform === "win32")(
    "exit 42 launches fresh once, exports the safety gate, then hot reload resumes with --continue",
    () => {
      const home = mkdtempSync(join(tmpdir(), "outpost-pi-restart-loop-"));
      try {
        const binDir = join(home, "bin");
        const remoteDir = join(home, "remote");
        const cwd = join(home, "cwd");
        const capture = join(home, "launches.txt");
        const counter = join(home, "counter.txt");
        mkdirSync(binDir);
        mkdirSync(remoteDir);
        mkdirSync(cwd);

        const fakePi = join(binDir, "pi");
        writeFileSync(fakePi, `#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "$COUNTER" ]; then count=$(<"$COUNTER"); fi
count=$((count + 1))
printf '%s' "$count" > "$COUNTER"
printf '%s|%s\\n' "\${OUTPOST_PI_UNDER_RESTART_WRAPPER:-}" "$*" >> "$CAPTURE"
case "$count" in
  1) exit ${EXIT_FRESH_SESSION} ;;
  2) touch "$OUTPOST_PI_HOME/.restart-marker-$$"; exit 0 ;;
  *) exit 0 ;;
esac
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

        const launches = readFileSync(capture, "utf8").trim().split("\n");
        expect(launches).toEqual([
          "1|--continue --model test-model",
          "1|--model test-model",
          "1|--continue --model test-model",
        ]);
      } finally {
        rmSync(home, { recursive: true, force: true });
      }
    },
    15_000,
  );
});
