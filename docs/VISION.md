# Outpost-Pi — Vision

Outpost-Pi is the mobile remote control and cross-PC agent mesh for the
[Pi coding agent](https://github.com/earendil-works/pi). Pair a phone via QR
over a relay, drive a Pi session from your pocket, watch tool calls stream in
real time, and let multiple Pi instances on your own PCs talk to each other
through a structured request/reply mesh.

Outpost-Pi is the continuation of the `remote_pi` project (see Provenance
below); the rebrand to Outpost-Pi is the fork's own name as a named product.

## Why this exists

Pi is the most relevant open-source competitor to Claude Code. It has a public
RPC and SDK — and, until Outpost-Pi, **no dedicated mobile app**. The only
existing mobile path was `TelePI`, a Telegram bot. Outpost-Pi fills that gap
with a first-class, open-source, quality-first mobile control surface and a
local agent mesh that no competing harness offers.

It does **not** compete with MuxAgent-style multi-harness commercial products.
The niche is Pi-only, open source, self-hostable.

## Who it is for

A developer who runs Pi as their coding agent and wants to:

- steer a session from a phone (send prompts, read streamed output, watch tool
  calls, swap models, compact context, start new sessions);
- keep coding agents on multiple of their own PCs mutually reachable — a
  mesh of Pi instances that exchange structured envelopes without a central
  orchestrator process;
- run a desktop "cockpit" that drives local Pi processes, terminals, file
  trees, and worktrees from one surface.

## What success looks like

- A paired phone is a real control surface for a Pi session — not a
  notification sink. Sending a prompt, compacting, switching model, and
  starting a new session all work end-to-end and converge cleanly.
- Multiple Pi instances on the same owner's PCs exchange messages with
  reliable delivery semantics and no cross-session contamination.
- The wire protocol is defined once and derived across TypeScript, Dart, and
  Rust — a change to the protocol is a one-place edit, not a coordinated
  hand-mirror across four locations.
- The relay is trivially self-hostable (~one Rust binary) and the trust model
  is honest about what it does and does not protect.
- A bug in one surface is local: lifecycle, reconnect, and state convergence
  are predictable and testable, not heuristic.

## What this is NOT

- **Not a multi-harness product.** Pi-only. No Claude Code, OpenCode, Goose,
  or Aider targets.
- **Not E2E encrypted today.** Transport is TLS; the relay sees plaintext
  envelope contents. Self-hosting is the mitigation; E2E is roadmap-additive.
  No product copy claims E2E.
- **Not a hosted/SaaS.** The relay is open source and self-hosted. There is no
  account server. Pairing is QR + Ed25519, peer-to-peer between an owner's
  devices.
- **Not a generic slash-command picker.** Mobile actions are a curated,
  typed vocabulary mapped to the Pi SDK's public API — not a mirror of the
  TUI's built-in command list.

## Fork posture & provenance

This checkout (`KevounC/remote_pi`) is a **hard fork** of
`jacobaraujo7/remote_pi`, rebranded **Outpost-Pi**. It has diverged past
upstream rebase (547 commits ahead, 0 upstream since the fork point as of
2026-07-02); the fork is the product, not a set of patches awaiting upstream.
Upstream remote (`jacobaraujo7/remote_pi`) is historical provenance and
read-only comparison, not a design constraint.

**Provenance is preserved.** Outpost-Pi is built on Jacob Moura's
`remote_pi`, MIT-licensed. The rebrand credits its origin in the LICENSE,
NOTICE, and README — it does not scrub the upstream author. See the
`epic-rebrand-to-outpost-pi` epic and `docs/DECISIONS.md` for the locked
naming, versioning, and identifier decisions.

The bold refactor is a fork-owned reconception of the absorbed codebase. It
is not a product divergence in scope — the product is still "mobile remote
control + cross-PC agent mesh for Pi." It is a structural reconception that
makes the absorbed codebase safe to bugfix against.

**Patchbay is the long-term play.** The bold refactor hardens the fork's
structure in the short term; patchbay is the intended successor direction
beyond carrying this fork. Bold-refactor design avoids decisions that would
block a future patchbay migration.

## Anti-vision (failure modes)

- A relay operator (including the public relay) can read message contents and
  metadata. Acceptable for a closed beta; unacceptable as the silent default
  for a wide audience without an honest UI and a self-host path.
- A contamination bug where session B's chat appears in session A's view — the
  system has no session discriminator on chat-bearing messages and relies on
  relay-room demux that fails open. This is the class of defect the bold
  refactor exists to eliminate.
- "Annoying to bugfix": a protocol change requiring coordinated hand-edits
  across TS/Dart/Rust with no compile-time signal. The generated-protocol
  epic exists to make this impossible by construction.

## Detailed references

- `PROTOCOL.md` — the canonical wire and security contract (detailed).
- `docs/DECISIONS.md` — the rolling-foundation decisions registry (locked
  product/architecture decisions). Read before re-opening any decision.
- `PROTOCOL.md` — the canonical wire and security contract (detailed).
- `docs/ARCHITECTURE.md`, `docs/SPEC.md` — companion foundation docs.

## Open questions

See `docs/SPEC.md` → "Open questions" for the consolidated list of genuine
ambiguities surfaced while authoring. None block the docs; all are flagged for
operator resolution so the foundation stays clean rather than baking in
guesses.
