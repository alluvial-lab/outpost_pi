import { chmod, writeFile } from "node:fs/promises";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Ed25519Keypair } from "../../pairing/crypto.js";
import { buildQRUri, clampPairTtlMs, qrSession, renderQRAscii, TOKEN_TTL_MS } from "../../pairing/qr.js";
import { listOwnerPubkeys, listPeers, removePeer } from "../../pairing/storage.js";
import { MeshClient } from "../../mesh/client.js";
import { SelfRevoke, type SiblingInfo } from "../../mesh/self_revoke.js";
import { roomIdFor } from "../../rooms.js";
import { localConfigExists } from "../../session/local_config.js";
import type { OwnerMultiplexerPort } from "../ports.js";

export type PairingCoordinatorState = "idle" | "started";

type PairingUiContext = Pick<ExtensionContext, "ui" | "cwd"> & Partial<Pick<ExtensionContext, "mode">>;

type PairingDialogTheme = {
  accent(text: string): string;
  dim(text: string): string;
};

/** Render a QR pairing code in a keyboard-dismissible TUI-only dialog. */
class PairingCodeDialog {
  private readonly qrLines: string[];
  private readonly expiresAtText: string;
  private readonly minimumWidth: number;

  constructor(
    qrAscii: string,
    private readonly qrUri: string,
    expiresAt: number,
    private readonly theme: PairingDialogTheme,
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
    if (width < this.minimumWidth) {
      return [
        `Terminal is too narrow for this pairing code; widen to ${this.minimumWidth} columns.`.slice(0, width),
        "Press Enter or Esc to close.".slice(0, width),
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
      ...wrapForTui(this.expiresAtText, width).map((line) => this.theme.dim(line)),
      ...wrapForTui("Press Enter or Esc to close.", width).map((line) => this.theme.dim(line)),
    ];
  }

  handleInput(data: string): void {
    if (data === "\r" || data === "\n" || data === "\x1b") this.done();
  }

  invalidate(): void {}
}

function wrapForTui(text: string, width: number): string[] {
  const lines: string[] = [];
  for (let start = 0; start < text.length; start += width) lines.push(text.slice(start, start + width));
  return lines.length > 0 ? lines : [""];
}

export interface PairingCoordinatorDeps {
  getState(): PairingCoordinatorState;
  startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void>;
  isRelayConnected(): boolean;
  roomId(): string | null;
  displayName(cwd: string): string;
  owners: OwnerMultiplexerPort;
  ownerHas(peerId: string): boolean;
  refreshPairingsCache(): void;
  joinLocalMesh(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void>;
  sendPiMessage(
    message: Parameters<ExtensionAPI["sendMessage"]>[0],
    options?: Parameters<ExtensionAPI["sendMessage"]>[1],
    label?: string,
  ): boolean;
  setSiblings(siblings: SiblingInfo[]): void;
}

function cwdFrom(ctx: Pick<ExtensionContext, "cwd">): string {
  return "cwd" in ctx && typeof ctx.cwd === "string" ? ctx.cwd : process.cwd();
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

  constructor(private readonly deps: PairingCoordinatorDeps) {}

  currentKeypair(): Ed25519Keypair | null {
    return this.cachedEd25519;
  }

  recordCurrentKeypair(keypair: Ed25519Keypair): void {
    this.cachedEd25519 = keypair;
  }

  stopSelfRevoke(): void {
    this.selfRevoke?.stop();
    this.selfRevoke = null;
  }

  startSelfRevoke(relayUrl: string, keypair: Ed25519Keypair): void {
    this.ensureSelfRevoke(relayUrl, keypair);
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
      // E2E-only headless observation seam. The production-generated bearer
      // token stays out of SDK messages/model context and is never logged.
      await writeFile(pairCodeFile, JSON.stringify({
        uri: qrUri,
        token,
        expiresAt,
        roomId,
        name: sessionName,
      }), { encoding: "utf8", mode: 0o600 });
      await chmod(pairCodeFile, 0o600);
    }

    if (ctx.mode !== "tui") return;
    const qrAscii = renderQRAscii(qrUri);
    await ctx.ui.custom<void>((_tui, theme, _keybindings, done) => new PairingCodeDialog(
      qrAscii,
      qrUri,
      expiresAt,
      {
        accent: (text) => theme.fg("accent", theme.bold(text)),
        dim: (text) => theme.fg("dim", text),
      },
      done,
    ));
  }

  async listDevices(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const peers = await listPeers();
    if (peers.length === 0) {
      ctx.ui.notify("[outpost-pi] No paired devices.", "info");
      return;
    }
    const lines = peers.map((p) => {
      const shortid = p.remote_epk.slice(0, 8);
      const tag = this.deps.ownerHas(p.remote_epk) ? " 🟢 online" : " ⚪ offline";
      return `• ${shortid} — ${p.name}${tag}`;
    }).join("\n");
    ctx.ui.notify(`[outpost-pi] Paired devices:\n${lines}`, "info");
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
    this.selfRevoke = new SelfRevoke({
      client: new MeshClient(relayUrl),
      storage: { listOwnerPubkeys, removePeer },
      myPubkey: edKp.publicKey,
      onRevoke: (ownerEpk) => {
        this.deps.refreshPairingsCache();
        if (this.deps.ownerHas(ownerEpk)) {
          this.deps.owners.detach(ownerEpk, "session_replaced");
        }
        const short = ownerEpk.slice(0, 8);
        this.deps.sendPiMessage({
          customType: "outpost-pi:mesh-revoked",
          content:
            `🔒 Revoked by Owner ${short}…\n\n` +
            `The mobile app for this Owner removed this PC from the mesh. ` +
            `Re-pair via /outpost-pi pair if this was unexpected.`,
          display: true,
        }, undefined, "mesh-revoked");
      },
      onMembersChanged: (siblings) => {
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
