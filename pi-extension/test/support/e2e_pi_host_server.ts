import { readFile, readdir, rm, writeFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { E2ePiHostRuntime } from "./e2e_pi_host_runtime.js";

const port = integerEnv("E2E_PI_HOST_PORT", 4317);
const relayUrl = requiredEnv("OUTPOST_PI_RELAY");
const cwd = process.env.E2E_PI_CWD ?? "/tmp/outpost-pi-e2e-cwd";
const seededTranscriptText = process.env.E2E_SEEDED_TRANSCRIPT ?? "e2e persisted transcript";
const preserveStateMarker = "/tmp/outpost-pi-e2e-preserve-state";
const preservedAgentName = await consumePreserveStateMarker();

// Boot line: printed synchronously at process start, BEFORE the awaited
// runtime start. If a wedged run shows ready-banners up to generation N and
// NO boot line for N+1, the container never restarted the process (docker-level);
// if the boot line IS present but no keyring warn follows, the process hung
// inside E2ePiHostRuntime.start() before the identity load. See
// backlog-pairing-e2e-flaky-auth-handshake-timeout (Mode B forensics).
process.stdout.write(`[e2e-pi-host] booting pid=${process.pid} node=${process.version}\n`);

const runtime = await E2ePiHostRuntime.start({
  relayUrl,
  cwd,
  seededTranscriptText,
  preserveState: preservedAgentName !== null,
  agentName: preservedAgentName ?? undefined,
});
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
  if (request.method === "GET" && url.pathname === "/debug-capture/latest") {
    const debugDir = `${cwd}/debug`;
    const files = (await readdir(debugDir))
      .filter((name) => /^app-capture-[A-Za-z0-9._-]+\.bin$/.test(name))
      .sort();
    const name = files.at(-1);
    if (!name) {
      json(response, 404, { error: "capture_not_found" });
      return;
    }
    const bytes = await readFile(`${debugDir}/${name}`);
    json(response, 200, {
      cwd,
      path: `debug/${name}`,
      bytes: bytes.length,
      content_base64: bytes.toString("base64"),
    });
    return;
  }
  if (request.method === "GET" && url.pathname === "/mesh") {
    json(response, 200, await runtime.meshStatus());
    return;
  }
  if (request.method === "POST" && url.pathname === "/mesh/refresh") {
    json(response, 200, { peers: await runtime.refreshMeshMembership() });
    return;
  }
  if (request.method === "POST" && url.pathname === "/mesh/target") {
    const body = await readJson(request);
    const pcPubkey = typeof body.pcPubkey === "string" ? body.pcPubkey : "";
    const remoteAddress = typeof body.remoteAddress === "string" ? body.remoteAddress : "";
    const target = pcPubkey && remoteAddress
      ? runtime.meshTarget(pcPubkey, remoteAddress)
      : null;
    if (!target) {
      json(response, 404, { error: "verified sibling target unavailable" });
      return;
    }
    json(response, 200, { target });
    return;
  }
  if (request.method === "POST" && url.pathname === "/mesh/send-direct") {
    const body = await readJson(request);
    const toPc = typeof body.toPc === "string" ? body.toPc : "";
    const toRoom = typeof body.toRoom === "string" ? body.toRoom : "";
    const toAddress = typeof body.toAddress === "string" ? body.toAddress : "";
    const message = typeof body.message === "string" ? body.message : "";
    if (!toPc || !toRoom || !toAddress || !message) {
      json(response, 400, { error: "toPc, toRoom, toAddress, and message are required" });
      return;
    }
    const sent = runtime.sendDirectMeshMessage({ toPc, toRoom, toAddress, message });
    json(response, sent ? 200 : 409, { sent });
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
    const body = await readJson(request);
    const reply = typeof body.reply === "string" ? body.reply : undefined;
    json(response, 200, runtime.deferNextTurn(reply));
    return;
  }
  if (request.method === "POST" && url.pathname === "/turn-control/resolve") {
    json(response, 200, runtime.resolveDeferredTurn());
    return;
  }
  if (request.method === "GET" && url.pathname === "/sessions") {
    json(response, 200, { active: runtime.status().sessionId, sessions: runtime.sessionIds() });
    return;
  }
  if (request.method === "POST" && url.pathname === "/session/switch") {
    const body = await readJson(request);
    const sessionId = typeof body.sessionId === "string" ? body.sessionId : "";
    if (!sessionId) {
      json(response, 400, { error: "sessionId is required" });
      return;
    }
    await runtime.switchSession(sessionId);
    json(response, 200, { active: runtime.status().sessionId });
    return;
  }
  if (request.method === "POST" && url.pathname === "/__restart") {
    if (restarting) {
      json(response, 409, { error: "restart already requested" });
      return;
    }
    restarting = true;
    const preserving = url.searchParams.get("preserve") === "1";
    if (preserving) {
      const assignedName = await runtime.preparePreservingRestart();
      process.stdout.write(`[e2e-pi-host] preserving assigned name=${assignedName}\n`);
      await writeFile(preserveStateMarker, assignedName, { mode: 0o600 });
    }
    json(response, 202, { restarting: true, generation: runtime.generation });
    setTimeout(() => process.exit(preserving ? 75 : 0), 25).unref();
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

async function consumePreserveStateMarker(): Promise<string | null> {
  try {
    const assignedName = await readFile(preserveStateMarker, "utf8");
    await rm(preserveStateMarker, { force: true });
    return assignedName.trim() || "e2e-agent";
  } catch {
    return null;
  }
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
