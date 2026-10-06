#!/usr/bin/env node
// Tailscale-severance repro harness (metronome verdict #6 follow-up).
//
// A slow-reading WebSocket client that is NOT the phone. It authenticates as
// its own app-style peer, subscribes to the same rooms/presence firehose the
// operator's phone receives (the pi-host daemon peer), and then reads that
// firehose SLOWLY through a duty-cycle throttle (socket pause/resume), so the
// relay->client path sees the same burst-then-backpressure shape the phone
// produces. Every inbound frame is counted + FNV-1a64 hashed with the exact
// basis of the relay's OutboundFrameHash instrument (relay/src/handlers/
// peer.rs), so a strike can be aligned against the relay's frames_out/out_hash
// the same way verdict #6 aligned the phone's capture.
//
// Legs (the point of the harness — WHO severs the tunnel):
//   A  --url ws://127.0.0.1:3300        on the VM, loopback: NO tailscale at
//                                        all. A strike here implicates the
//                                        relay-side/VM-internal path (the
//                                        relay logs its own closes, so a
//                                        relay kill is self-identifying).
//   B  --url ws://<relay-tailnet-ip>:3300 from a DIFFERENT tailnet node
//                                        (laptop): full tunnel path. A strike
//                                        there implicates VM tailscaled or
//                                        router NAT and is upstream-
//                                        reportable with a minimal repro.
//   If only the phone ever strikes, the phone's tailscale app / Android is
//   the secerer.
//
// NOTE on leg A vs self-tailnet: connecting to the VM's own tailnet IP from
// the VM routes via `lo` (local table) — it does NOT traverse tailscaled and
// is equivalent to leg A. A real leg B needs a second tailnet node.
//
// Strike taxonomy (client-visible classification):
//   abrupt-reset / abrupt-eof  — no close frame; the socket died under us.
//                                Relay log should show IO-104 for our peer =>
//                                the severance signature we are hunting.
//   relay-close:<reason>       — clean server close (e.g.
//                                relay_outbound_mailbox_saturated: our
//                                throttle is slower than the mailbox bound;
//                                benign, relay-initiated, logged by relay).
//   watchdog-silent            — no inbound for --watchdog-ms while reading
//                                is enabled (relay pings every 25s): the
//                                silent-blackhole variant of severance (no
//                                RST delivered), e.g. NAT state expiry.
//
// Pause-window caveat: while paused we do not read, so a relay close frame
// sent mid-pause is only seen on resume. Keep --pause-ms well under
// --watchdog-ms. Abrupt resets surface immediately even while paused (RST
// delivery is not gated on reads).
//
// Usage examples:
//   node e2e/severance_harness.mjs --label A-localhost --url ws://127.0.0.1:3300
//   node e2e/severance_harness.mjs --label B-laptop --url ws://100.106.7.<relay>:3300 \
//       --read-ms 500 --pause-ms 2000
//   node e2e/severance_harness.mjs --fast            # unthrottled control
//
// Output: JSONL rows to e2e/.run-state/severance/<label>-<ts>.jsonl plus a
// one-line summary on stdout per connection event. Correlate strikes with:
//   docker logs outpost-pi-relay --since <t> 2>&1 | grep 'stream error'
// using the peer short printed in the header row (last 8 chars of the
// harness pubkey, matching relay's peer_short).

import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
// The repo has no root node_modules; resolve `ws` through the pi-extension
// install (ws is a runtime dep there and has no hard deps of its own).
const requireFromExt = createRequire(path.join(here, '..', 'pi-extension', 'package.json'));
const WebSocket = requireFromExt('ws');

// --- ct flood (phone-shape burst reproduction) ---------------------------------
// The phone's metronome bursts are NOT rooms/presence snapshots (a full 19-room
// snapshot is ~5.6KB; identically-subscribed harness peers never saw >10KB
// frames) — they are daemon→phone ct rehydration envelopes (~730KB + ~400KB
// pairs per reconnect). ct is opaque to the relay, so two harness peers can
// reproduce the exact wire shape (huge frames into a slow reader) without any
// pairing: the SINK (--flood-peer) pokes the FLOODER (--serve-flood) after
// each (re)connect, and the flooder answers with the burst pair.

const FLOOD_ROOM_DEFAULT = 'harness-bench';
const FLOOD_GAP_MS = 8000; // second frame lands ~8s after the first (phone cadence)

function envelopeFrame(destPk, room, payloadBytes) {
  return JSON.stringify({
    peer: destPk,
    room,
    ct: crypto.randomBytes(payloadBytes).toString('base64'),
  });
}

// JSON overhead ≈ fixed keys + b64 expansion: payload = (target - overhead)·3/4
function payloadBytesForTargetFrame(targetFrameBytes) {
  const overhead = 96;
  return Math.max(1, Math.round(((targetFrameBytes - overhead) * 3) / 4));
}

// --- CLI ---------------------------------------------------------------------

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--fast') {
      out.readMs = 0;
      out.pauseMs = 0;
      continue;
    }
    if (a === '--help' || a === '-h') {
      out.help = true;
      continue;
    }
    if (!a.startsWith('--')) throw new Error(`unexpected arg ${a}`);
    const key = a.slice(2);
    const val = argv[++i];
    if (val === undefined) throw new Error(`missing value for ${a}`);
    out[key] = val;
  }
  return out;
}

const HELP = `Usage: severance_harness.mjs [options]
  --url <ws://host:port>   relay URL (default ws://127.0.0.1:3300)
  --label <name>           leg name; used in identity + output file (required-ish)
  --peers <b64[,b64...]>   epks to subscribe to (default: pi-host daemon pk
                           from ~/.pi/remote/identity.json)
  --identity <path>        identity file (default .run-state/severance/identity-<label>.json,
                           generated on first use)
  --device-id <str>        hello device_id (default severance-harness-<label>)
  --room <id>              hello room_id (default main)
  --read-ms <n>            duty cycle: read window ms (default 500)
  --pause-ms <n>           duty cycle: pause window ms, 0 = no throttle (default 2000)
  --reconnect-ms <n>       reconnect delay (default 2000)
  --watchdog-ms <n>        silent-blackhole threshold while reading (default 60000)
  --provoke-every-ms <n>   periodic rooms_check+presence_check burst (default 0 = off)
  --cycle-every-ms <n>     force a clean reconnect every n ms — mimics the
                           phone's metronome cycle (reconnect → snapshot
                           replay burst → quiet) without waiting for strikes
                           (default 0 = off)
  --flood-peer <pk>        SINK mode: auth into --flood-room and poke this
                           flooder peer after every (re)connect so it sends
                           the ct burst pair at this slow reader
  --flood-room <room>      room for sink/flooder (default harness-bench)
  --serve-flood <pk:big:small>  FLOODER mode: auth into --flood-room; on every
                           poke envelope from the sink send ct frames sized
                           big/small (target frame bytes, phone-shaped)
  --duration-min <n>       stop after n minutes (default 0 = until Ctrl-C)
  --out <path>             JSONL output path (default auto)
  --fast                   shorthand for --read-ms 0 --pause-ms 0`;

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  console.log(HELP);
  process.exit(0);
}

const cfg = {
  url: args.url ?? 'ws://127.0.0.1:3300',
  label: args.label ?? 'leg',
  readMs: Number(args['read-ms'] ?? 500),
  pauseMs: Number(args['pause-ms'] ?? 2000),
  reconnectMs: Number(args['reconnect-ms'] ?? 2000),
  watchdogMs: Number(args['watchdog-ms'] ?? 60_000),
  provokeEveryMs: Number(args['provoke-every-ms'] ?? 0),
  cycleEveryMs: Number(args['cycle-every-ms'] ?? 0),
  floodPeer: args['flood-peer'] ?? null,
  floodRoom: args['flood-room'] ?? FLOOD_ROOM_DEFAULT,
  serveFlood: args['serve-flood'] ?? null,
  durationMin: Number(args['duration-min'] ?? 0),
  deviceId: (args['device-id'] ?? `severance-harness-${args.label ?? 'leg'}`).slice(0, 128),
  room: args.room ?? 'main',
};
if (cfg.serveFlood) {
  const parts = cfg.serveFlood.split(':');
  if (parts.length !== 3) {
    console.error('--serve-flood expects <sinkPk>:<bigFrameBytes>:<smallFrameBytes>');
    process.exit(2);
  }
  cfg.serveFlood = { sinkPk: parts[0], big: Number(parts[1]), small: Number(parts[2]) };
  cfg.room = cfg.floodRoom; // flooder must be reachable in the flood room
}
if (cfg.floodPeer) cfg.room = cfg.floodRoom; // sink likewise
if (!Number.isFinite(cfg.readMs) || !Number.isFinite(cfg.pauseMs)) {
  console.error('read-ms/pause-ms must be numbers');
  process.exit(2);
}

// --- Identity (ed25519, raw 32B keys like the app/extension) ------------------

const ED_PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');

function seedToPrivateKey(seed) {
  if (seed.length !== 32) throw new Error('ed25519 seed must be 32 bytes');
  const der = Buffer.concat([ED_PKCS8_PREFIX, seed]);
  return crypto.createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
}

function seedToPublicPk(seed) {
  const priv = seedToPrivateKey(seed);
  const spki = crypto.createPublicKey(priv).export({ type: 'spki', format: 'der' });
  // Raw pk is the last 32 bytes of the SPKI structure.
  return Buffer.from(spki.subarray(spki.length - 32));
}

function generateIdentity() {
  const seed = crypto.randomBytes(32);
  return { sk: seed.toString('base64'), pk: seedToPublicPk(seed).toString('base64') };
}

function loadOrCreateIdentity(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (parsed?.sk && parsed?.pk) return parsed;
  } catch {
    /* generate below */
  }
  const id = generateIdentity();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(id, null, 2) + '\n');
  return id;
}

const stateDir = path.join(here, '.run-state', 'severance');
const identityFile = args.identity ?? path.join(stateDir, `identity-${cfg.label}.json`);
const identity = loadOrCreateIdentity(identityFile);
const seed = Buffer.from(identity.sk, 'base64');
const privateKey = seedToPrivateKey(seed);
const pubB64 = identity.pk; // trust the stored pk; regenerated identically from seed anyway
const peerShort = pubB64.slice(-8);

function signAuth(nonceBytes) {
  // Mirrors relayAuthSigningBytes: utf8("outpost-pi-relay-auth-v1\n") ++ nonce
  // (relay/src/auth/challenge.rs verify_auth; keep in lockstep).
  const prefix = Buffer.from('outpost-pi-relay-auth-v1\n', 'utf8');
  const msg = Buffer.concat([prefix, nonceBytes]);
  return crypto.sign(null, msg, privateKey);
}

// --- Frame hash instrument (mirrors relay OutboundFrameHash) -------------------

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x00000100000001b3n;
const MASK = 0xffffffffffffffffn;

function fnv1a64(bytes) {
  let h = FNV_OFFSET;
  for (const b of bytes) h = ((h ^ BigInt(b)) * FNV_PRIME) & MASK;
  return h;
}

function foldRunning(running, idx, frameHash) {
  let h = running;
  const folded = Buffer.alloc(16);
  folded.writeBigUInt64LE(idx);
  folded.writeBigUInt64LE(frameHash, 8);
  for (const b of folded) h = ((h ^ BigInt(b)) * FNV_PRIME) & MASK;
  return h;
}

const hex16 = (v) => v.toString(16).padStart(16, '0');

// --- Output -------------------------------------------------------------------

const outPath =
  args.out ?? path.join(stateDir, `${cfg.label}-${new Date().toISOString().replace(/[:.]/g, '-')}.jsonl`);
fs.mkdirSync(path.dirname(outPath), { recursive: true });
const outStream = fs.createWriteStream(outPath, { flags: 'a' });

function row(obj) {
  outStream.write(JSON.stringify({ t: new Date().toISOString(), ...obj }) + '\n');
}

function log(...msg) {
  console.log(`[${new Date().toISOString()}]`, ...msg);
}

// --- Peers to subscribe to ------------------------------------------------------

function defaultPeers() {
  const idFile = path.join(os.homedir(), '.pi', 'remote', 'identity.json');
  try {
    const pk = JSON.parse(fs.readFileSync(idFile, 'utf8')).pk;
    if (typeof pk === 'string' && pk.length > 8) return [pk];
  } catch {
    /* fall through */
  }
  throw new Error(`no --peers given and could not read pi-host identity at ${idFile}`);
}

const peers = args.peers ? args.peers.split(',').map((s) => s.trim()).filter(Boolean) : defaultPeers();

// --- Connection lifecycle --------------------------------------------------------

const startedAt = Date.now();
let connSeq = 0;
let stopping = false;
let active = null; // current WebSocket, for shutdown teardown

const header = {
  ev: 'header',
  label: cfg.label,
  url: cfg.url,
  peers,
  pubkey: pubB64,
  peerShort,
  identityFile,
  device_id: cfg.deviceId,
  room: cfg.room,
  readMs: cfg.readMs,
  pauseMs: cfg.pauseMs,
  watchdogMs: cfg.watchdogMs,
  provokeEveryMs: cfg.provokeEveryMs,
  cycleEveryMs: cfg.cycleEveryMs,
  floodPeer: cfg.floodPeer,
  floodRoom: cfg.floodRoom,
  serveFlood: cfg.serveFlood
    ? { sinkPk: cfg.serveFlood.sinkPk, big: cfg.serveFlood.big, small: cfg.serveFlood.small }
    : null,
  node: process.version,
  host: os.hostname(),
  out: outPath,
};
row(header);
log(
  `harness ${cfg.label} -> ${cfg.url} as peer_short=${peerShort} ` +
    `(grep relay logs for 'peer=${peerShort}'), throttled read=${cfg.readMs}ms pause=${cfg.pauseMs}ms`,
);
log(`output: ${outPath}`);

function shutdown(reason) {
  if (stopping) return;
  stopping = true;
  row({ ev: 'end', reason, uptimeMs: Date.now() - startedAt });
  log(`stopping: ${reason}`);
  for (const t of timersToClear) clearTimeout(t);
  active?.terminate();
  setTimeout(() => process.exit(0), 250).unref();
}process.on('SIGINT', () => shutdown('sigint'));
process.on('SIGTERM', () => shutdown('sigterm'));

const timersToClear = [];

function connectOnce() {
  if (stopping) return;
  if (cfg.durationMin > 0 && Date.now() - startedAt > cfg.durationMin * 60_000) {
    shutdown('duration');
    return;
  }

  const conn = ++connSeq;
  const ws = new WebSocket(cfg.url, { handshakeTimeout: 8000 });
  active = ws;
  let sock = null;
  let authed = false;
  let subscribed = false;
  let framesIn = 0;
  let bytesIn = 0;
  let runHash = FNV_OFFSET;
  let lastFrame = null;
  let openedAt = null;
  let paused = false;
  let lastInboundAt = Date.now();
  let dutyTimer = null;
  let classifyDone = false;
  let cycleRequested = false;

  const send = (obj, stage) => {
    const text = JSON.stringify(obj);
    ws.send(text);
    row({ ev: 'send', conn, stage, bytes: Buffer.byteLength(text) });
  };

  ws.on('unexpected-response', (_req, res) => {
    row({ ev: 'http-reject', conn, status: res.statusCode });
  });

  ws.on('open', () => {
    sock = ws._socket;
    openedAt = Date.now();
    lastInboundAt = Date.now();
    row({ ev: 'open', conn, remote: `${sock.remoteAddress}:${sock.remotePort}` });
    send(
      { type: 'hello', pubkey: pubB64, device_id: cfg.deviceId, room_id: cfg.room },
      'hello',
    );
    // Handshake guard (relay closes unauthenticated sockets after 5s per step).
    const guard = setTimeout(() => {
      if (!authed) {
        row({ ev: 'auth-timeout', conn });
        ws.close(4000, 'harness auth timeout');
      }
    }, 12_000);
    timersToClear.push(guard);
    ws.once('close', () => {
      clearTimeout(guard);
      timersToClear.splice(timersToClear.indexOf(guard), 1);
    });
  });

  ws.on('message', (data, isBinary) => {
    lastInboundAt = Date.now();
    let parsed = null;
    if (!isBinary) {
      try {
        parsed = JSON.parse(data.toString('utf8'));
      } catch {
        /* treat as opaque */
      }
    }

    if (!authed) {
      if (parsed?.type === 'challenge') {
        const nonce = Buffer.from(parsed.nonce, 'base64');
        const sig = signAuth(nonce);
        send({ type: 'auth', sig: sig.toString('base64') }, 'auth');
        send({ type: 'presence_check', peers: [] }, 'readiness-probe'); // mirrors the app
        // NO early return: the challenge frame must be counted below — the
        // relay's OutboundFrameHash counts it too (sent via send_instrumented),
        // so skipping it here would misalign every idx/hash comparison.
      } else if (parsed?.type) {
        // First post-auth frame = readiness boundary (relay has no auth ACK).
        authed = true;
        log(`conn ${conn}: authenticated`);
        if (cfg.serveFlood) {
          // FLOODER: no subscriptions, no duty cycle; the poke listener in the
          // frame handler below does the work.
        } else if (!subscribed) {
          subscribed = true;
          // Mirrors ConnectionManager.subscribeToPeers exactly (lockstep
          // presence + rooms, then one-shot snapshots for hydration).
          send({ type: 'subscribe_presence', peers }, 'subscribe');
          send({ type: 'subscribe_rooms', peers }, 'subscribe');
          send({ type: 'presence_check', peers }, 'subscribe');
          send({ type: 'rooms_check', peers }, 'subscribe');
          if (cfg.floodPeer) {
            // SINK: poke the flooder so this reconnect's burst lands on THIS
            // connection — the daemon→phone rehydration shape.
            send(JSON.parse(envelopeFrame(cfg.floodPeer, cfg.floodRoom, 1)), 'flood-poke');
          }
        }
        if (!cfg.serveFlood) startDutyCycle();
      }
      // fall through to frame accounting below for this frame too
    }

    // Frame accounting over the relay's hash basis (Text frames: payload utf8
    // bytes — the Buffer ws hands us IS those bytes; Binary: raw bytes).
    framesIn += 1;
    bytesIn += data.length;
    const frameHash = fnv1a64(data);
    runHash = foldRunning(runHash, BigInt(framesIn), frameHash);
    lastFrame = { idx: framesIn, bytes: data.length, hash: hex16(frameHash) };
    const kind =
      parsed?.type ?? (isBinary ? 'binary' : parsed?.ct !== undefined ? 'envelope' : 'json?');
    row({
      ev: 'frame',
      conn,
      idx: framesIn,
      bytes: data.length,
      hash: hex16(frameHash),
      run: hex16(runHash),
      kind,
    });

    // FLOODER: every inbound typeless envelope is a poke from the sink —
    // answer with the phone-shaped ct burst pair on this connection.
    if (cfg.serveFlood && parsed && parsed.ct !== undefined && parsed.type === undefined) {
      send(
        JSON.parse(
          envelopeFrame(
            cfg.serveFlood.sinkPk,
            cfg.floodRoom,
            payloadBytesForTargetFrame(cfg.serveFlood.big),
          ),
        ),
        'flood-big',
      );
      setTimeout(
        () =>
          ws.readyState === WebSocket.OPEN &&
          send(
            JSON.parse(
              envelopeFrame(
                cfg.serveFlood.sinkPk,
                cfg.floodRoom,
                payloadBytesForTargetFrame(cfg.serveFlood.small),
              ),
            ),
            'flood-small',
          ),
        FLOOD_GAP_MS,
      );
    }
  });

  ws.on('ping', () => {
    lastInboundAt = Date.now();
    row({ ev: 'ping', conn });
  });
  ws.on('pong', () => {
    lastInboundAt = Date.now();
  });

  function startDutyCycle() {
    if (cfg.pauseMs <= 0 || cfg.readMs <= 0 || dutyTimer) return;
    const cycle = () => {
      if (ws.readyState !== WebSocket.OPEN) return;
      paused = true;
      sock?.pause();
      dutyTimer = setTimeout(() => {
        if (ws.readyState !== WebSocket.OPEN) return;
        paused = false;
        lastInboundAt = Date.now(); // resume-deadline baseline for the watchdog
        sock?.resume();
        dutyTimer = setTimeout(cycle, cfg.readMs);
      }, cfg.pauseMs);
    };
    dutyTimer = setTimeout(cycle, cfg.readMs);
  }

  // Watchdog: reading is enabled (not paused) and STILL nothing inbound for
  // watchdogMs — the relay pings every 25s, so this is a dead path (the
  // silent-blackhole severance variant — no RST ever arrives). Doubles as
  // the --cycle-every-ms driver: a clean local close starts the next cycle.
  const watchdog = setInterval(() => {
    if (ws.readyState !== WebSocket.OPEN || !authed) return;
    if (
      cfg.cycleEveryMs > 0 &&
      openedAt &&
      Date.now() - openedAt > cfg.cycleEveryMs &&
      !cycleRequested
    ) {
      cycleRequested = true;
      recordStrike('local-cycle', null, `forced reconnect after ${Date.now() - openedAt}ms`);
      ws.close(1000, 'harness cycle');
      return;
    }
    const quietFor = Date.now() - lastInboundAt;
    if (!paused && quietFor > cfg.watchdogMs) {
      recordStrike('watchdog-silent', null, `no inbound for ${quietFor}ms while reading`);
      ws.terminate(); // 'close' handler records + schedules the reconnect
    }
  }, 5000);
  timersToClear.push(watchdog);

  function recordStrike(kind, closeEvt, detail) {
    if (classifyDone) return;
    classifyDone = true;
    row({
      ev: 'strike',
      conn,
      kind,
      detail,
      code: closeEvt?.code ?? null,
      reason: closeEvt?.reason ?? null,
      wasClean: closeEvt?.wasClean ?? null,
      uptimeMs: openedAt ? Date.now() - openedAt : null,
      framesIn,
      bytesIn,
      runIn: hex16(runHash),
      lastFrame,
    });
    log(
      `STRIKE conn ${conn}: ${kind}${detail ? ` (${detail})` : ''} code=${closeEvt?.code ?? '-'} ` +
        `reason=${closeEvt?.reason ?? '-'} framesIn=${framesIn} bytesIn=${bytesIn} runIn=${hex16(runHash)}`,
    );
  }

  ws.on('error', (err) => {
    // RST surfaces here (ECONNRESET) — the severance signature.
    if (err.code === 'ECONNRESET') recordStrike('abrupt-reset', null, err.message);
    row({ ev: 'ws-error', conn, code: err.code ?? null, msg: String(err.message) });
  });

  ws.on('close', (code, reason) => {
    clearTimeout(dutyTimer);
    const reasonText = reason?.toString('utf8') ?? '';
    const closeEvt = { code, reason: reasonText, wasClean: code !== 1006 };
    if (!classifyDone) {
      if (stopping) recordStrike('local-shutdown', closeEvt);
      else if (cycleRequested) recordStrike('local-cycle-done', closeEvt);
      else if (code === 1006) recordStrike('abrupt-eof', closeEvt, 'abnormal closure, no close frame');
      else if (reasonText.startsWith('relay_')) recordStrike(`relay-close:${reasonText}`, closeEvt);
      else recordStrike(`server-close:${code}`, closeEvt, reasonText || null);
    }
    row({ ev: 'close', conn, code, reason: reasonText, framesIn, bytesIn, runIn: hex16(runHash) });
    log(`conn ${conn} closed (code=${code} reason=${reasonText || '-'}); reconnect in ${cfg.reconnectMs}ms`);
    scheduleReconnect();
  });

  // Optional burst provocation: one-shot snapshot requests on an interval.
  if (cfg.provokeEveryMs > 0) {
    const provoke = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN && authed) {
        send({ type: 'rooms_check', peers }, 'provoke');
        send({ type: 'presence_check', peers }, 'provoke');
      }
    }, cfg.provokeEveryMs);
    timersToClear.push(provoke);
  }
}

let reconnectTimer = null;
function scheduleReconnect() {
  if (stopping) return;
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectOnce();
  }, cfg.reconnectMs);
  timersToClear.push(reconnectTimer);
}

// Periodic beat rows for gap-free telemetry.
const beat = setInterval(() => {
  row({ ev: 'beat', uptimeMs: Date.now() - startedAt, label: cfg.label });
}, 5000);
timersToClear.push(beat);

// Duration cap (checked globally — a long-lived connection never re-enters
// connectOnce, where the reconnect-time check alone would never fire).
if (cfg.durationMin > 0) {
  const stop = setTimeout(() => shutdown('duration'), cfg.durationMin * 60_000);
  timersToClear.push(stop);
}

connectOnce();
