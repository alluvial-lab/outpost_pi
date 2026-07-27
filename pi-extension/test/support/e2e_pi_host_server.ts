import { readFile, rm } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { E2ePiHostRuntime } from "./e2e_pi_host_runtime.js";

const port = integerEnv("E2E_PI_HOST_PORT", 4317);
const relayUrl = requiredEnv("OUTPOST_PI_RELAY");
const cwd = process.env.E2E_PI_CWD ?? "/tmp/outpost-pi-e2e-cwd";
const seededTranscriptText = process.env.E2E_SEEDED_TRANSCRIPT ?? "e2e persisted transcript";

const runtime = await E2ePiHostRuntime.start({ relayUrl, cwd, seededTranscriptText });
let restarting = false;

const server = createServer(async (request, response) => {
  try {
    await route(request, response);
  } catch (error) {
    json(response, 500, { error: safeReason(error) });
  }
});

server.listen(port, "0.0.0.0", () => {
  process.stdout.write(`[e2e-pi-host] ready port=${port} generation=${runtime.generation}\n`);
});

async function route(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
  if (request.method === "GET" && url.pathname === "/health") {
    json(response, runtime.status().relayConnected ? 200 : 503, { ok: runtime.status().relayConnected });
    return;
  }
  if (request.method === "GET" && url.pathname === "/status") {
    json(response, 200, runtime.status());
    return;
  }
  if (request.method === "GET" && url.pathname === "/events") {
    const after = Number.parseInt(url.searchParams.get("after") ?? "0", 10);
    json(response, 200, { events: runtime.eventsAfter(Number.isFinite(after) ? after : 0) });
    return;
  }
  if (request.method === "GET" && url.pathname === "/pair-code") {
    const path = requiredEnv("OUTPOST_PI_PAIR_CODE_FILE");
    const pairCode = JSON.parse(await readFile(path, "utf8")) as unknown;
    json(response, 200, pairCode);
    return;
  }
  if (request.method === "DELETE" && url.pathname === "/pair-code") {
    // Mirror the Cockpit seam contract: the consumer removes the pair-code
    // file when the attempt ends, so a later `pair` command in the same
    // process generation does not hit the extension's refuse-to-overwrite
    // hardening (assertPairCodeTargetAbsent).
    const path = requiredEnv("OUTPOST_PI_PAIR_CODE_FILE");
    await rm(path, { force: true });
    json(response, 200, { ok: true });
    return;
  }
  if (request.method === "POST" && url.pathname === "/command") {
    const body = await readJson(request);
    const args = typeof body.args === "string" ? body.args : "";
    await runtime.invokeOutpostPi(args);
    json(response, 200, { ok: true });
    return;
  }
  if (request.method === "GET" && url.pathname === "/turn-control") {
    json(response, 200, runtime.turnControlStatus());
    return;
  }
  if (request.method === "POST" && url.pathname === "/turn-control/defer-next") {
    json(response, 200, runtime.deferNextTurn());
    return;
  }
  if (request.method === "POST" && url.pathname === "/turn-control/resolve") {
    json(response, 200, runtime.resolveDeferredTurn());
    return;
  }
  if (request.method === "POST" && url.pathname === "/__restart") {
    if (restarting) {
      json(response, 409, { error: "restart already requested" });
      return;
    }
    restarting = true;
    json(response, 202, { restarting: true, generation: runtime.generation });
    setTimeout(() => process.exit(0), 25).unref();
    return;
  }
  json(response, 404, { error: "not_found" });
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let bytes = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    bytes += buffer.length;
    if (bytes > 16_384) throw new Error("request_too_large");
    chunks.push(buffer);
  }
  if (chunks.length === 0) return {};
  const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid_json_object");
  return parsed as Record<string, unknown>;
}

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(body));
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function integerEnv(name: string, fallback: number): number {
  const value = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

function safeReason(error: unknown): string {
  return error instanceof Error && error.name ? error.name : "unknown_error";
}

async function shutdown(): Promise<void> {
  server.close();
  await runtime.dispose().catch(() => undefined);
}

process.once("SIGTERM", () => { void shutdown().finally(() => process.exit(0)); });
process.once("SIGINT", () => { void shutdown().finally(() => process.exit(0)); });
