# Outpost-Pi — Relay (Rust)

**Stateless** WebSocket server that pairs connections by `peer_id` and routes
ciphertext between the app and pi-extension. **It never decrypts payloads.**

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

- Relay **NEVER** decrypts payloads — all content is opaque ciphertext
- Only metadata is visible: `peer_id`, size, timestamp
- Logs **MUST NOT** contain payloads, even encrypted ones
- Rate limit by `peer_id` and source IP

## Must not do

- Do not use `println!` (use `tracing`)
- Do not use `.unwrap()` or `.expect()` on production paths
- Do not log message contents
- Do not add payload persistence — the relay is stateless
- Do not commit `target/` (already in the root `.gitignore`)

## Orchestrated mode

If you receive a prompt beginning with `[ORCH:<task-id>]`, read
`../.orchestration/INSTRUCTIONS.md` before taking any other action. This marker
indicates that another agent is coordinating the work and has specific rules
(where to write the result, do not commit, and so on).
