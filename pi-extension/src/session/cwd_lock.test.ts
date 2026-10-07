import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, type ChildProcess } from "node:child_process";
import { createRequire } from "node:module";
import {
  acquireCwdLock,
  acquireUniqueNamedCwdLock,
  lockPathForCwd,
  lockPathFor,
} from "./cwd_lock.js";

/** A fresh tmp cwd per test — each gets a unique room hash, so tests in
 *  parallel don't fight over the same lock socket. */
function tmpCwd(): string {
  return mkdtempSync(join(tmpdir(), "pi-cwdlock-"));
}

/** Redirect the lock dir away from the developer's real `~/.pi/remote/locks`
 *  so running the suite never binds sockets in the live mesh's directory.
 *
 *  Base it on a SHORT root (`/tmp`), NOT `os.tmpdir()`: the lock socket nests
 *  `<home>/.pi/remote/locks/<12-char>.sock`, and on macOS `os.tmpdir()` is a
 *  deep `/var/folders/…/T/` path that pushes the socket past the ~104-char UDS
 *  path limit → `bind` fails → `acquireCwdLock` returns `ok:false` and these
 *  tests fail (and break `prepublishOnly`). `/tmp` keeps the full path short. */
let testHome: string;

beforeEach(() => {
  testHome = mkdtempSync("/tmp/rp-cwdlock-");
  process.env["OUTPOST_PI_HOME"] = testHome;
});

afterEach(() => {
  delete process.env["OUTPOST_PI_HOME"];
  try { rmSync(testHome, { recursive: true, force: true }); } catch { /* best-effort */ }
});

describe("acquireCwdLock", () => {
  test("first call acquires; second call (same cwd) is refused", async () => {
    const cwd = tmpCwd();

    const first = await acquireCwdLock(cwd);
    expect(first.ok).toBe(true);

    const second = await acquireCwdLock(cwd);
    expect(second.ok).toBe(false);
    if (!second.ok) {
      expect(second.lockPath).toBe(lockPathForCwd(cwd));
    }

    if (first.ok) first.release();
  });

  test("releasing the lock allows a fresh acquire", async () => {
    const cwd = tmpCwd();

    const first = await acquireCwdLock(cwd);
    expect(first.ok).toBe(true);
    if (first.ok) first.release();

    // Some platforms keep the socket file around after close — the lock
    // primitive must self-heal via the stale-detect-then-unlink path.
    const second = await acquireCwdLock(cwd);
    expect(second.ok).toBe(true);
    if (second.ok) second.release();
  });

  test("different cwds get independent locks", async () => {
    const cwdA = tmpCwd();
    const cwdB = tmpCwd();

    const a = await acquireCwdLock(cwdA);
    const b = await acquireCwdLock(cwdB);

    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect(lockPathForCwd(cwdA)).not.toBe(lockPathForCwd(cwdB));

    if (a.ok) a.release();
    if (b.ok) b.release();
  });

  // The stale-socket self-heal path (a previous Pi died WITHOUT releasing
  // the lock — `kill -9` or crash) can't be reproduced reliably from a
  // single Node process: depending on Node version + OS, `server.close()`
  // either unlinks the socket file or leaves it behind. We rely on the
  // existing leader-election tests (which DO exercise the unlink-retry
  // path via real broker crashes in `src/session/leader_election.test.ts`)
  // to cover the OS primitive, and trust that `acquireCwdLock` composes
  // it correctly. Manual repro: `kill -9` a Pi process holding the lock,
  // then run `/outpost-pi` again — acquires cleanly.

  test("same cwd, DIFFERENT names → independent locks (multi-agent per folder)", async () => {
    const cwd = tmpCwd();
    const a = await acquireCwdLock(cwd, "backend");
    const b = await acquireCwdLock(cwd, "frontend");

    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true); // different name in the same folder is allowed
    expect(lockPathFor(cwd, "backend")).not.toBe(lockPathFor(cwd, "frontend"));

    if (a.ok) a.release();
    if (b.ok) b.release();
  });

  test("same cwd, SAME name → refused (per-(cwd,name) singleton)", async () => {
    const cwd = tmpCwd();
    const first = await acquireCwdLock(cwd, "backend");
    expect(first.ok).toBe(true);

    const second = await acquireCwdLock(cwd, "backend");
    expect(second.ok).toBe(false);
    if (!second.ok) expect(second.lockPath).toBe(lockPathFor(cwd, "backend"));

    if (first.ok) first.release();
  });

  test("named lock is independent from the legacy cwd-only lock", async () => {
    const cwd = tmpCwd();
    const named = await acquireCwdLock(cwd, "backend");
    const legacy = await acquireCwdLock(cwd); // no name → old room-id lock
    expect(named.ok).toBe(true);
    expect(legacy.ok).toBe(true);
    expect(lockPathFor(cwd, "backend")).not.toBe(lockPathForCwd(cwd));
    if (named.ok) named.release();
    if (legacy.ok) legacy.release();
  });

  test("refused result includes the canonical lockPath", async () => {
    const cwd = tmpCwd();
    const held = await acquireCwdLock(cwd);
    expect(held.ok).toBe(true);

    const refused = await acquireCwdLock(cwd);
    expect(refused.ok).toBe(false);
    if (!refused.ok) {
      // Same hash → same path, regardless of which call computes it.
      expect(refused.lockPath).toBe(lockPathForCwd(cwd));
    }

    if (held.ok) held.release();
  });
});

describe("acquireUniqueNamedCwdLock (coexistence suffix walk)", () => {
  test("free requested name locks under it directly", async () => {
    const cwd = tmpCwd();
    const unique = await acquireUniqueNamedCwdLock(cwd, "backend");
    expect(unique?.ok).toBe(true);
    expect(unique?.name).toBe("backend");
    unique?.lock.release();
  });

  test("held base name coexists under #2; freed #2 is reused before #3", async () => {
    const cwd = tmpCwd();
    const base = await acquireCwdLock(cwd, "Backoffice");
    expect(base.ok).toBe(true);

    const second = await acquireUniqueNamedCwdLock(cwd, "Backoffice");
    expect(second?.ok).toBe(true);
    expect(second?.name).toBe("Backoffice#2");

    second?.lock.release();
    // The walk always starts at the base: with #2 freed it takes #2 again,
    // never skipping straight to #3 (matches the broker's identity walk).
    const third = await acquireUniqueNamedCwdLock(cwd, "Backoffice");
    expect(third?.name).toBe("Backoffice#2");

    third?.lock.release();
    if (base.ok) base.release();
  });

  test("walks past every held suffix", async () => {
    const cwd = tmpCwd();
    const locks = [
      await acquireCwdLock(cwd, "api"),
      await acquireCwdLock(cwd, "api#2"),
      await acquireCwdLock(cwd, "api#3"),
    ];
    expect(locks.every((l) => l.ok)).toBe(true);

    const unique = await acquireUniqueNamedCwdLock(cwd, "api");
    expect(unique?.name).toBe("api#4");

    unique?.lock.release();
    for (const l of locks) if (l.ok) l.release();
  });

  test("returns null when the walk is exhausted", async () => {
    const cwd = tmpCwd();
    const held = await acquireCwdLock(cwd, "solo");
    expect(held.ok).toBe(true);

    const unique = await acquireUniqueNamedCwdLock(cwd, "solo", 1);
    expect(unique).toBeNull();

    if (held.ok) held.release();
  });
});

// Abrupt host death (kill -9) must not orphan the lock: the OS tears the
// socket listener down with the process, and the next acquirer self-heals
// through the ECONNREFUSED → unlink → rebind path. The old comment here
// punted this to manual repro; a real subprocess makes it a regression
// test (story-mcp-endpoint-lock-ownership, folded from
// idea-mesh-server-orphan-lock-shutdown).
describe.skipIf(process.platform === "win32")("cwd lock survives holder kill -9", () => {
  test("SIGKILLed holder leaves a re-acquirable lock", async () => {
    const cwd = tmpCwd();
    const projectRoot = fileURLToPath(new URL("../..", import.meta.url));
    // Run the holder via tsx's loader entry points DIRECTLY (what `tsx <file>`
    // spawns under the hood). Going through the tsx CLI adds a supervisor
    // parent, and SIGKILL on the supervisor can orphan the real holder —
    // exactly the leak this test exists to catch.
    const tsxPreflight = createRequire(import.meta.url).resolve("tsx/preflight");
    const tsxLoader = pathToFileURL(
      tsxPreflight.replace(/preflight\.cjs$/, "loader.mjs"),
    ).href;
    // Child script: hold the (cwd, name) lock, print ready, never exit.
    const script = join(testHome, "hold-lock.mts");
    writeFileSync(script, [
      `import { acquireCwdLock } from ${JSON.stringify(join(projectRoot, "src", "session", "cwd_lock.ts"))};`,
      `const lock = await acquireCwdLock(process.env["LOCK_CWD"]!, process.env["LOCK_NAME"]);`,
      `if (!lock.ok) { console.error("child: lock refused"); process.exit(1); }`,
      `console.log("ready");`,
      `setInterval(() => {}, 1 << 30);`,
      ``,
    ].join("\n"));

    const child: ChildProcess = spawn(
      process.execPath,
      ["--require", tsxPreflight, "--import", tsxLoader, script],
      {
        env: { ...process.env, LOCK_CWD: cwd, LOCK_NAME: "victim" },
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    let out = "";
    child.stdout!.setEncoding("utf8");
    child.stdout!.on("data", (chunk: string) => { out += chunk; });
    let err = "";
    child.stderr!.setEncoding("utf8");
    child.stderr!.on("data", (chunk: string) => { err += chunk; });

    // Wait for the child to actually hold the lock (bounded).
    const deadline = Date.now() + 15_000;
    while (!out.includes("ready") && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 100));
      if (child.exitCode !== null) throw new Error(`holder child exited early (${child.exitCode}): ${err}`);
    }
    expect(out).toContain("ready");
    // A refused second acquire PROVES the live child holds it (not just that
    // a socket file exists).
    const liveRefusal = await acquireCwdLock(cwd, "victim");
    expect(liveRefusal.ok).toBe(false);

    child.kill("SIGKILL");
    const exited = new Promise<void>((resolve) => child.once("exit", resolve));
    await exited;

    // After the hard kill, the same (cwd, name) lock re-acquires cleanly.
    const reacquired = await acquireCwdLock(cwd, "victim");
    expect(reacquired.ok).toBe(true);
    if (reacquired.ok) reacquired.release();
  }, 25_000);
});
