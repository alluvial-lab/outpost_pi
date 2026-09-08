---
id: story-metronome-paired-frame-hash-instrument
kind: story
stage: implementing
tags: [app, relay, workflow]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: null
created: 2026-09-08
updated: 2026-09-08
---

# Paired frame-hash instrument: settle metronome corruption origin in one strike

Design (from story-fix-connection-metronome-death probe-map addendum):
relay hashes every frame it writes to the phone; app hashes every message
dart delivers. One strike decides: relay wrote frame k (hash known) that
the app never received as a message + 1002 → corruption between relay
userspace and dart parse (VM-internal path prime suspect); matching hashes
with a parse error → dart itself (falsifiable).

## Units

1. **Relay** — peer outbound write path (handlers/peer.rs): per-connection
   frame counter + FNV-1a64 running hash of each outbound payload;
   per-frame DEBUG line (compact); extend the existing disconnect/stream-
   error WARN line with `frames_out=<n> out_hash=<x>`. Ciphertext/JSON
   bytes only — never decode. DEBUG-gated per relay logging discipline.
2. **App** — WsTransport listen callback: per-connection inbound counter +
   FNV-1a64 per message, added as fields to EXISTING wsIn rows (no new
   capture events — the 1MiB buffer is already retention-limited); extend
   connChannelLost rows with the inbound counter+hash at loss.

## Acceptance

- Relay unit test: counter+hash correctness across frames; disconnect line
  carries them. `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green.
- App test: wsIn rows carry h/idx fields; connChannelLost carries the
  counter/hash. `flutter analyze && flutter test --exclude-tags e2e` green
  (sync_service load-flake = isolation-green bar).
- Both sides' hashes computable from the same test vector (document the
  exact FNV basis in both code files so the comparison is apples-to-apples).

Bound to v0.12.0 (operator 2026-09-08) — rides rc.2; targeted gates on
completion (tests + security minimum: payload-derived data in logs).
