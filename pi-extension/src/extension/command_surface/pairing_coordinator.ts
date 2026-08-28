import { constants } from "node:fs";
import { lstat, open, rename, rm } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { basename, dirname, join } from "node:path";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Ed25519Keypair } from "../../pairing/crypto.js";
import { buildQRUri, clampPairTtlMs, qrSession, renderQRAscii, TOKEN_TTL_MS } from "../../pairing/qr.js";
import { listOwnerPubkeys, listPeers, removePeer } from "../../pairing/storage.js";
import { MeshClient } from "../../mesh/client.js";
import { SelfRevoke, type SelfRevokeOptions, type SiblingInfo } from "../../mesh/self_revoke.js";
import { roomIdFor } from "../../rooms.js";
import { localConfigExists } from "../../session/local_config.js";
import type { OwnerMultiplexerPort } from "../ports.js";
import type { SystemStatusEvent } from "../system_status_event.js";
import { Osc52Clipboard, type ClipboardPort } from "./clipboard.js";

export type PairingCoordinatorState = "idle" | "started";

type PairingUiContext = Pick<ExtensionContext, "ui" | "cwd"> & Partial<Pick<ExtensionContext, "mode">>;

type PairingDialogTheme = {
  accent(text: string): string;
  dim(text: string): string;
};

type PairingDialogTui = {
  requestRender(): void;
};

type PairingCopyState = "copying" | "copied" | "failed";

/** Render a QR pairing code and offer an exact clipboard copy action. */
export class PairingCodeDialog {
  private readonly qrLines: string[];
  private readonly expiresAtText: string;
  private readonly minimumWidth: number;
  private copyState: PairingCopyState | undefined;

  constructor(
    qrAscii: string,
    private readonly qrUri: string,
    expiresAt: number,
    private readonly theme: PairingDialogTheme,
    private readonly tui: PairingDialogTui,
    private readonly clipboard: ClipboardPort,
    private readonly done: () => void,
  ) {
    this.qrLines = qrAscii.trimEnd().split("\n");
    this.expiresAtText = `Valid until ${new Date(expiresAt).toLocaleTimeString()}.`;
    this.minimumWidth = Math.max(
      ...this.qrLines.map((line) => line.length),
      "Press Enter or Esc to close.".length,
    );
  }

  render(width: number): string[] {
    const copyHint = this.copyState === undefined
      ? "Press c to copy pairing code."
      : this.copyState === "copying"
        ? "Copying pairing code…"
        : this.copyState === "copied"
          ? "Pairing code copied to clipboard."
          : "Clipboard copy failed.";
    const copyHintLines = wrapForTui(copyHint, width).map((line) => this.copyState === "copied"
      ? this.theme.accent(line)
      : this.theme.dim(line));
    const closeHintLines = wrapForTui("Press Enter or Esc to close.", width).map((line) => this.theme.dim(line));

    if (width < this.minimumWidth) {
      // The QR won't fit, but the camera-less URI path is exactly what a
      // narrow terminal needs — show it wrapped rather than hiding the only
      // usable pairing code behind a width gate.
      return [
        ...wrapForTui("Terminal is too narrow for the QR; copy this pairing code instead:", width),
        "",
        ...wrapForTui(this.qrUri, width),
        "",
        ...copyHintLines,
        ...wrapForTui(this.expiresAtText, width).map((line) => this.theme.dim(line)),
        ...closeHintLines,
      ];
    }
    return [
      this.theme.accent("Scan to pair"),
      "",
      ...this.qrLines,
      "",
      ...wrapForTui("Or copy this pairing code (camera-less devices):", width),
      "",
      ...wrapForTui(this.qrUri, width),
      "",
      ...copyHintLines,
      ...wrapForTui(this.expiresAtText, width).map((line) => this.theme.dim(line)),
      ...closeHintLines,
    ];
  }

  handleInput(data: string): void {
    if (data === "c" || data === "C") {
      void this.copyPairingCode();
      return;
    }
    if (data === "\r" || data === "\n" || data === "\x1b") this.done();
  }

  invalidate(): void {}

  private async copyPairingCode(): Promise<void> {
    if (this.copyState === "copying") return;
    this.copyState = "copying";
    this.tui.requestRender();
    try {
      await this.clipboard.copy(this.qrUri);
      this.copyState = "copied";
    } catch {
      this.copyState = "failed";
    }
    this.tui.requestRender();
  }
}

function wrapForTui(text: string, width: number): string[] {
  const lines: string[] = [];
  for (let start = 0; start < text.length; start += width) lines.push(text.slice(start, start + width));
  return lines.length > 0 ? lines : [""];
}

/**
 * Supply the relay, owner-channel, mesh, and Pi-message adapters for pairing commands.
 *
 * The composition root owns relay/session teardown and supplies only live adapters;
 * this coordinator owns its cached identity and self-revoke poller, stopping the
 * latter through {@link PairingCoordinator.stopSelfRevoke} on replacement.
 */
export interface PairingCoordinatorDeps {
  getState(): PairingCoordinatorState;
  /** Resolve the live session UI after asynchronous pairing setup. */
  currentUi?(): Pick<PairingUiContext["ui"], "custom" | "notify"> | undefined;
  /** Copy pairing URIs without coupling the dialog to a platform clipboard API. */
  clipboard?: ClipboardPort;
  startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void>;
  isRelayConnected(): boolean;
  roomId(): string | null;
  displayName(cwd: string): string;
  owners: OwnerMultiplexerPort;
  ownerHas(peerId: string): boolean;
  refreshPairingsCache(): void;
  joinLocalMesh(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void>;
  emitStatusEvent(event: SystemStatusEvent): boolean;
  setSiblings(siblings: SiblingInfo[]): void;
}

function isStaleContextError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("stale after session replacement or reload");
}

function cwdFrom(ctx: Pick<ExtensionContext, "cwd">): string {
  return "cwd" in ctx && typeof ctx.cwd === "string" ? ctx.cwd : process.cwd();
}

/** Reject a configured seam target that already resolves to any filesystem entry. */
async function assertPairCodeTargetAbsent(target: string): Promise<void> {
  try {
    const targetStat = await lstat(target);
    const kind = targetStat.isSymbolicLink() ? "symlink" : "filesystem entry";
    throw new Error(`Pair code file already exists as a ${kind}: ${target}`);
  } catch (error: unknown) {
    if (typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT") return;
    throw error;
  }
}

/** Publish the headless pairing payload without ever writing bearer bytes to an existing file. */
async function writePairCodeFile(target: string, payload: string): Promise<void> {
  await assertPairCodeTargetAbsent(target);
  const temporary = join(dirname(target), `.${basename(target)}.${randomUUID()}.tmp`);
  let handle: Awaited<ReturnType<typeof open>> | undefined;

  try {
    handle = await open(
      temporary,
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL,
      0o600,
    );
    await handle.writeFile(payload, "utf8");
    await handle.sync();
    await handle.close();
    handle = undefined;

    // Recheck to reject a target created while the private temporary file was written.
    await assertPairCodeTargetAbsent(target);
    await rename(temporary, target);
  } finally {
    await handle?.close();
    await rm(temporary, { force: true });
  }
}

/**
 * Owns relay-facing pairing commands plus their long-lived resources.
 *
 * The extension root remains the composition boundary for relay/session/owner
 * ports, while the cached Pi identity and self-revoke poller have one lifecycle
 * owner here.
 */
export class PairingCoordinator {
  private cachedEd25519: Ed25519Keypair | null = null;
  private selfRevoke: SelfRevoke | null = null;
  private verifiedSiblingsForTest: SiblingInfo[] = [];
  private listDevicesUi: PairingUiContext["ui"] | null = null;
  private readonly clipboard: ClipboardPort;

  constructor(
    private readonly deps: PairingCoordinatorDeps,
    private readonly createSelfRevoke: (options: SelfRevokeOptions) => SelfRevoke =
      (options) => new SelfRevoke(options),
  ) {
    this.clipboard = deps.clipboard ?? new Osc52Clipboard();
  }

  currentKeypair(): Ed25519Keypair | null {
    return this.cachedEd25519;
  }

  recordCurrentKeypair(keypair: Ed25519Keypair): void {
    this.cachedEd25519 = keypair;
  }

  stopSelfRevoke(): void {
    this.selfRevoke?.stop();
    this.selfRevoke = null;
    this.verifiedSiblingsForTest = [];
  }

  startSelfRevoke(relayUrl: string, keypair: Ed25519Keypair): void {
    this.ensureSelfRevoke(relayUrl, keypair);
  }

  /** Run one membership sweep for test adapters without changing production cadence. */
  async refreshMembershipForTest(): Promise<void> {
    await this.selfRevoke?.checkOnce();
  }

  /** Build a test route only from signed membership and a broker-issued remote address. */
  meshTargetForTest(pcPubkey: string, remoteAddress: string): string | null {
    const canonicalPubkey = Buffer.from(pcPubkey, "base64").toString("base64");
    const sibling = this.verifiedSiblingsForTest.find(
      (candidate) => candidate.pcPubkey === canonicalPubkey,
    );
    return sibling ? `${sibling.pcLabel}:${remoteAddress}` : null;
  }

  async startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    await this.deps.startRelay(ctx);
  }

  /** Show a QR pairing token without adding it to model context. */
  async showPairQr(ctx: PairingUiContext, args = ""): Promise<void> {
    const pairCodeFile = process.env["OUTPOST_PI_PAIR_CODE_FILE"];
    if (ctx.mode !== "tui" && !pairCodeFile) {
      ctx.ui.notify("[outpost-pi] Pairing QR display requires an interactive TUI session.", "warning");
      return;
    }

    const cwd = cwdFrom(ctx);

    if (this.deps.getState() === "idle") {
      if (!localConfigExists(cwd)) {
        ctx.ui.notify(
          "[outpost-pi] First-time setup needed. Run /outpost-pi to configure, then /outpost-pi pair.",
          "warning",
        );
        return;
      }
      ctx.ui.notify("[outpost-pi] Starting mesh + relay before pairing…", "info");
      await this.deps.joinLocalMesh(ctx);
      if (this.deps.getState() === "idle") await this.startRelay(ctx);
    }

    if (!this.deps.isRelayConnected()) {
      ctx.ui.notify(
        "[outpost-pi] Pair requires the relay to be connected. " +
        "Run /outpost-pi to start it (or fix your relay URL via /outpost-pi set-relay).",
        "warning",
      );
      return;
    }

    const edKp = this.cachedEd25519;
    if (!edKp) {
      ctx.ui.notify("[outpost-pi] Identity is not loaded yet. Run /outpost-pi to reconnect, then pair.", "warning");
      return;
    }
    const sessionName = this.deps.displayName(cwd);
    const ttlMatch = /--ttl\s+(\d+)/.exec(args);
    const ttlMs = ttlMatch ? clampPairTtlMs(Number(ttlMatch[1]) * 1000) : TOKEN_TTL_MS;
    const { token, expiresAt } = qrSession.issueToken(ttlMs);
    const roomId = this.deps.roomId() ?? roomIdFor(cwd, sessionName);
    const qrUri = buildQRUri(token, edKp.publicKey, sessionName, roomId);

    if (pairCodeFile) {
      // Headless pairing-code retrieval seam for Cockpit and the E2E harness.
      // Its production-generated bearer token stays out of SDK messages/model
      // context and logs; publishing uses a private temporary file + rename.
      await writePairCodeFile(pairCodeFile, JSON.stringify({
        uri: qrUri,
        token,
        expiresAt,
        roomId,
        name: sessionName,
      }));
    }

    if (ctx.mode !== "tui") return;
    const qrAscii = renderQRAscii(qrUri);
    // Relay/mesh setup and pair-code publication above can outlive the command
    // session. Production supplies currentUi, so never fall back to a captured
    // command capability when the current session has already shut down. The
    // fallback only preserves isolated coordinator fixtures without a runtime.
    const dialogUi = this.deps.currentUi?.()
      ?? (this.deps.currentUi === undefined ? ctx.ui : undefined);
    if (!dialogUi) return;
    try {
      await dialogUi.custom<void>((tui, theme, _keybindings, done) => new PairingCodeDialog(
        qrAscii,
        qrUri,
        expiresAt,
        {
          accent: (text) => theme.fg("accent", theme.bold(text)),
          dim: (text) => theme.fg("dim", text),
        },
        tui,
        this.clipboard,
        done,
      ));
    } catch (error) {
      // A successor can replace even the freshly resolved UI while the dialog
      // is opening. Session replacement closes this command as a safe no-op.
      if (!isStaleContextError(error)) throw error;
    }
  }

  async listDevices(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const ui = ctx.ui;
    this.listDevicesUi = ui;
    const peers = await listPeers();
    if (peers.length === 0) {
      this.notifyListDevices(ui, "[outpost-pi] No paired devices.");
      return;
    }
    const lines = peers.map((p) => {
      const shortid = p.remote_epk.slice(0, 8);
      const tag = this.deps.ownerHas(p.remote_epk) ? " 🟢 online" : " ⚪ offline";
      return `• ${shortid} — ${p.name}${tag}`;
    }).join("\n");
    this.notifyListDevices(ui, `[outpost-pi] Paired devices:\n${lines}`);
  }

  private notifyListDevices(ui: PairingUiContext["ui"], message: string): void {
    try {
      ui.notify(message, "info");
    } catch (error) {
      if (isStaleContextError(error)) {
        if (this.listDevicesUi === ui) this.listDevicesUi = null;
        return;
      }
      throw error;
    }
  }

  async revokeDevice(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    const shortid = arg.trim();
    if (!shortid) {
      ctx.ui.notify(
        "[outpost-pi] Usage: /outpost-pi revoke <shortid>. Run /outpost-pi list to see shortids.",
        "warning",
      );
      return;
    }

    const cwd = cwdFrom(ctx);
    if (this.deps.getState() === "idle") {
      if (!localConfigExists(cwd)) {
        ctx.ui.notify(
          "[outpost-pi] First-time setup needed. Run /outpost-pi to configure, then /outpost-pi revoke.",
          "warning",
        );
        return;
      }
      ctx.ui.notify("[outpost-pi] Starting mesh + relay before revoking…", "info");
      await this.deps.joinLocalMesh(ctx);
      if (this.deps.getState() === "idle") await this.startRelay(ctx);
    }
    if (!this.deps.isRelayConnected()) {
      ctx.ui.notify(
        "[outpost-pi] Revoke requires the relay to be connected. " +
        "Run /outpost-pi to start it (or fix your relay URL via /outpost-pi set-relay).",
        "warning",
      );
      return;
    }

    const peers = await listPeers();
    const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));

    if (matches.length === 0) {
      ctx.ui.notify(
        `[outpost-pi] No peer matching '${shortid}'. Run /outpost-pi list to see shortids.`,
        "warning",
      );
      return;
    }

    if (matches.length > 1) {
      const collisions = matches.map((p) => p.remote_epk.slice(0, 8)).join(", ");
      ctx.ui.notify(
        `[outpost-pi] Ambiguous shortid — ${matches.length} matches: ${collisions}. Use more characters.`,
        "warning",
      );
      return;
    }

    const peer = matches[0]!;
    if (this.deps.ownerHas(peer.remote_epk)) {
      // Persist and send the final protected bye while its channel record still
      // exists; removing the record first would fence the mandatory send
      // high-water write and expose no frame.
      await this.deps.owners.detach(peer.remote_epk, "session_replaced");
    }
    await removePeer(peer.remote_epk);
    this.deps.refreshPairingsCache();

    ctx.ui.notify(
      `[outpost-pi] Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`,
      "info",
    );
  }

  private ensureSelfRevoke(relayUrl: string, edKp: Ed25519Keypair): void {
    if (this.selfRevoke !== null) return;
    this.selfRevoke = this.createSelfRevoke({
      client: new MeshClient(relayUrl),
      storage: { listOwnerPubkeys, removePeer },
      myPubkey: edKp.publicKey,
      onRevoke: async (ownerEpk): Promise<void> => {
        this.deps.refreshPairingsCache();
        if (this.deps.ownerHas(ownerEpk)) {
          await this.deps.owners.detach(ownerEpk, "session_replaced");
        }
        const short = ownerEpk.slice(0, 8);
        const message =
          `Revoked by Owner ${short}…\n\n` +
          `The mobile app for this Owner removed this PC from the mesh. ` +
          `Re-pair via /outpost-pi pair if this was unexpected.`;
        try {
          this.deps.currentUi?.()?.notify(message, "warning");
        } catch {
          // A replacement may invalidate the UI between lookup and notification.
        }
        this.deps.emitStatusEvent({
          customType: "outpost-pi:mesh-revoked",
          details: { owner: short },
        });
      },
      onMembersChanged: (siblings) => {
        this.verifiedSiblingsForTest = [...siblings];
        this.deps.setSiblings(siblings);
      },
      log: { info: () => {}, warn: () => {}, error: () => {} },
    });
    this.selfRevoke.start();
  }
}

export function pairingShortidCompletions(
  prefix: string,
  valuePrefix = "",
): Promise<Array<{ value: string; label: string }>> {
  return listPeers()
    .then((peers) => peers
      .map((p) => ({ shortid: p.remote_epk.slice(0, 8), name: p.name }))
      .filter((x) => x.shortid.startsWith(prefix))
      .map((x) => ({ value: `${valuePrefix}${x.shortid}`, label: `${x.shortid} (${x.name})` })));
}
