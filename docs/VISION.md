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
- **Owner payloads are E2E-protected; relay-visible metadata is not.**
  Post-pairing app↔Pi owner payloads use the protected owner channel. The relay
  still sees routing metadata and cross-PC Pi↔Pi envelope contents; self-hosting
  remains the mitigation for that visibility.
- **Not a hosted/SaaS.** The relay is open source and self-hosted. There is no
  account server. Pairing is QR + Ed25519, peer-to-peer between an owner's
  devices.
- **Not a generic slash-command picker.** Mobile actions are a curated,
  typed vocabulary mapped to the Pi SDK's public API — not a mirror of the
  TUI's built-in command list.

## Provenance

Outpost-Pi is derived from Jacob Moura's `remote_pi`, MIT-licensed. The rebrand
credits its origin in the LICENSE, NOTICE, and README — it does not scrub the
original author. See `docs/DECISIONS.md` for the locked naming, versioning,
and identifier decisions.

The bold refactor is a reconception of the codebase. It is not a product
divergence in scope — the product is still "mobile remote
control + cross-PC agent mesh for Pi." It is a structural reconception that
makes the codebase safe to bugfix against.

**Patchbay is the long-term play.** The bold refactor hardens the product's
structure in the short term; patchbay is the intended successor direction.
Bold-refactor design avoids decisions that would block a future patchbay
migration.

## Anti-vision (failure modes)

- The operator-controlled relay can read routing metadata and cross-PC Pi↔Pi
  envelope contents, but not post-pairing app↔Pi owner payloads. Users who need
  to limit relay exposure can self-host the relay.
- A regression that lets session B's chat appear in session A's view.
  Session-scoped pushes carry a canonical, required `session_id`, and the app
  rejects missing or foreign IDs before mutating state; any path that bypasses
  either boundary violates session isolation.
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
