import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createServer, connect, type Server, type Socket } from "node:net";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { Broker } from "./broker.js";
import { uuidv7 } from "./envelope.js";

/** Minimal newline-framed JSON line client for the local UDS broker. */
class LineClient {
  readonly lines: string[] = [];
  private waiters: Array<{ predicate: (line: string) => boolean; resolve: (line: string) => void }> = [];
  private closed = false;

  constructor(readonly socket: Socket) {
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      let nl: number;
      let buf = chunk;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!line) continue;
        const waiter = this.waiters.find((w) => w.predicate(line));
        if (waiter) {
          this.waiters.splice(this.waiters.indexOf(waiter), 1);
          waiter.resolve(line);
        } else {
          this.lines.push(line);
        }
      }
    });
  }

  send(obj: unknown): void {
    this.socket.write(JSON.stringify(obj) + "\n");
  }

  /** Resolves with the next line matching `predicate` (backlog included). */
  async waitFor(predicate: (line: string) => boolean, timeoutMs = 2_000): Promise<string> {
    const backlog = this.lines.find(predicate);
    if (backlog !== undefined) {
      this.lines.splice(this.lines.indexOf(backlog), 1);
      return backlog;
    }
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        const i = this.waiters.indexOf(waiter);
        if (i >= 0) this.waiters.splice(i, 1);
        reject(new Error("waitFor timed out"));
      }, timeoutMs);
      const waiter = { predicate, resolve: (line: string) => { clearTimeout(timer); resolve(line); } };
      this.waiters.push(waiter);
    });
  }

  close(): void {
    if (!this.closed) {
      this.closed = true;
      this.socket.destroy();
    }
  }
}

describe("broker invalid-envelope handling (fail loud, never silent)", () => {
  let server: Server;
  let broker: Broker;
  let dir: string;
  let auditPath: string;
  let sockPath: string;
  const clients: LineClient[] = [];

  beforeAll(async () => {
    dir = mkdtempSync(join(tmpdir(), "pi-inv-env-"));
    auditPath = join(dir, "audit.jsonl");
    sockPath = join(dir, "broker.sock");
    server = createServer();
    broker = new Broker({ server, auditPath });
    await new Promise<void>((resolve) => server.listen(sockPath, resolve));
  });

  afterAll(async () => {
    for (const c of clients) c.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(dir, { recursive: true, force: true });
  });

  async function register(name: string, cwd: string): Promise<LineClient> {
    const socket = await new Promise<Socket>((resolve, reject) => {
      const s = connect(sockPath, () => resolve(s));
      s.on("error", reject);
    });
    const client = new LineClient(socket);
    clients.push(client);
    client.send({ type: "register", name, cwd });
    await client.waitFor((line) => line.includes("register_ack"));
    return client;
  }

  test("non-UUID re: NACK invalid_envelope keyed by the sent id + audit trace", async () => {
    const alpha = await register("alpha", "/tmp/inv");
    const id = uuidv7();
    alpha.send({ from: "spoofed-ignored", to: "/tmp/inv@beta", id, re: "item-model-primitives", body: "x" });

    const nackLine = await alpha.waitFor((line) => line.includes("invalid_envelope"));
    const nack = JSON.parse(nackLine) as { from: string; to: string; re: string; body: { type: string; status: string } };
    expect(nack.from).toBe("broker");
    expect(nack.re).toBe(id); // keyed by the sent id → sender's sendWithAck resolves
    expect(nack.body.type).toBe("ack");
    expect(nack.body.status).toBe("invalid_envelope");

    // Audit trail: the rejection is visible with its reason (not silently gone).
    await delay(50); // audit append is chained async
    const audit = readFileSync(auditPath, "utf8").trim().split("\n");
    const rejected = audit.map((l) => JSON.parse(l) as Record<string, unknown>)
      .find((e) => e.ack_status === "invalid_envelope");
    expect(rejected).toBeDefined();
    expect(String(rejected!.error)).toContain("re must be null or UUID");
    expect(String(rejected!.from)).toContain("alpha");
    expect(rejected!.delivered).toEqual([]);
  });

  test("UUID re in the same session still routes and ACKs received", async () => {
    const alpha = clients[0]!;
    const beta = await register("beta", "/tmp/inv");
    const id = uuidv7();
    alpha.send({ from: "ignored", to: "/tmp/inv@beta", id, re: uuidv7(), body: { control: true } });

    const got = JSON.parse(await beta.waitFor((line) => line.includes("control"))) as { re: string | null };
    expect(got.re).not.toBe("item-model-primitives"); // parsed as a valid envelope
    const ackLine = await alpha.waitFor((line) => line.includes('"ack"') && line.includes(id));
    const ack = JSON.parse(ackLine) as { body: { status: string } };
    expect(ack.body.status).toBe("received");
  });
});
