# Outpost-Pi — Relay (Rust)

WebSocket server that pairs connections by `peer_id` and forwards app↔Pi and
cross-PC traffic. Its direct listener serves cleartext `ws://`; use `wss://`
only behind an external TLS-terminating reverse proxy. The reference deployment
uses plain `ws://` on a LAN/tailnet. App↔Pi owner-channel payloads are
app-layer E2E ciphertext (opaque to the relay), while cross-PC Pi↔Pi payloads
remain relay-readable plaintext; routing handlers treat all payloads as opaque
and never log them. Message routing has no durable queue. The relay persists
only signed mesh membership in SQLite and keeps room, presence, registry, and
metrics state in memory.

Before editing or reviewing relay code, read the agent-neutral Rust relay reference at `../.agents/skills/rust-relay/SKILL.md`.

## Stack

- Rust 1.94+ (2024 edition)
- Runtime: `tokio` (full features)
- WebSocket: `tokio-tungstenite`
- Serialization: `serde` + `serde_json`
- Logging: `tracing` + `tracing-subscriber` (**do not** use `println!`)

## Commands

- `cargo build` — development build
- `cargo build --release` — optimized build
- `cargo run` — run locally
- `RUST_LOG=info cargo run` — run with visible logs
- `cargo clippy -- -D warnings` — strict lint (must pass before commit)
- `cargo fmt` — format
- `cargo test` — tests

## Conventions

- **Errors**: `anyhow::Result<()>` in `main`, `thiserror::Error` in internal libraries
- **Async**: everything through `tokio::spawn` / `tokio::select!`, no `std::thread`
- **Logging**: `info!`/`warn!`/`error!` with fields directly in handlers (no `info_span!`); spans are reserved for cross-handler trace context, not per-call handler logging
- **No `unwrap()`** in production code. Use `?` and propagate.
- **No unnecessary `clone()`** — pass `&` where possible

## Security policy

- The direct listener is cleartext `ws://`; use an external TLS-terminating
  reverse proxy when transport encryption (`wss://`) is required. The app↔Pi
  owner channel carries app-layer E2E-encrypted payloads
  (`outpost-pi-owner-channel-v1` sealed frames — the relay sees ciphertext);
  cross-PC Pi↔Pi payloads are NOT E2E and remain relay-readable
- Routing code treats payload contents as opaque and does not inspect them for
  application behavior
- Logs **MUST NOT** contain payload contents
- Rate limits are per connection: cross-PC forwarding attempts and
  presence/rooms control-check peer cost

## Must not do

- Do not use `println!` (use `tracing`)
- Do not use `.unwrap()` or `.expect()` on production paths
- Do not log message contents
- Do not add payload/message persistence or an offline queue; durable storage
  is limited to signed mesh-membership records
- Do not commit `target/` (already in the root `.gitignore`)

## Orchestrated mode

If you receive a prompt beginning with `[ORCH:<task-id>]`, read
`../.orchestration/INSTRUCTIONS.md` before taking any other action. This marker
indicates that another agent is coordinating the work and has specific rules
(where to write the result, do not commit, and so on).
