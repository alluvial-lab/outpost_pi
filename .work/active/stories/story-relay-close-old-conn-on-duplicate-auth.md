---
id: story-relay-close-old-conn-on-duplicate-auth
kind: story
stage: implementing
tags: [relay, bug, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-10
---

# Relay: close the old conn(s) at a key when a duplicate authenticates

## Brief

When a mobile peer reconnects after a network switch (wifi→cellular), the old
TCP path is typically **half-open** (no FIN/RST reaches the relay). The relay's
`ConnectionRegistry::insert()` pushes the new conn onto the `Vec` for the
`(peer, room)` key and sets `superseded_existing: true` as a flag — but does
**not** close or remove the old conn's `tx`. The old half-open conn stays in
the `Vec` until its own socket times out via the 25 s WS ping, and during that
window `send_to_room` fans out to **both** conns (the live one and the
half-open one whose `tx.send()` will eventually fail on an unbounded queue).

This makes mobile recovery latency gated by ping timeout rather than by the
reconnect itself, and feeds `gate-security-unbounded-outbound-queues` (the
half-open conn buffers forwarded frames until reaped). The fix: when a
duplicate authenticates at the same `(peer, room)` key, actively close the
prior conn(s) so recovery is immediate. No wire change, no app change — the
`superseded_existing` flag already identifies the case; the missing step is
closing the prior `tx`(s).

## Observed (live drop test, 2026-07-02)

Between the local reconnect (`18:03:50Z`, `192.168.40.136:57586`) and the
wireguard reconnect (`18:07:17Z`, `192.168.11.2:54008`) there was **no
`disconnected` log on the relay** for the first connection. The phone left
wifi (so the local TCP went half-open — no FIN/RST reached the relay), and
the wireguard auth arrived as a **duplicate connection** for the same peer id
(`/uV6O0I=`).

The relay's registry handled it and recovered (last-conn-wins / old times out
via ping), so the session resumed. But there is a window where the relay
considers two connections to exist for one peer id, and promptness of cleanup
depends on the **ping timeout**, not a socket close.

## Why it matters

- This is the normal case for mobile: switching wifi↔cellular rarely gives a
  clean TCP teardown. So detection speed is gated by ping interval/timeout,
  not the OS.
- The relay sends a WS Ping every 25 s (`relay/src/handlers/peer.rs:123`), so a
  half-open peer is only reaped after a ping goes unacknowledged — order of
  tens of seconds, possibly more depending on TCP keepalive settings.
- Contributes to the slow recovery in `idea-mobile-drop-slow-recovery` and the
  duplicate-connection window.

## Code-confirmed behavior (2026-07-10) — answers the prior design-time questions

## Prior design-time questions (resolved below)

- Is 25 s ping + TCP keepalive the right detection speed for mobile network
  transitions, or should the app send an explicit "I'm replacing my
  connection" signal on reconnect so the relay can drop the old conn eagerly?
- The relay already handles duplicate-connection takeover (last-conn-wins);
  should that path be the primary mechanism rather than waiting for ping
  timeout on the old conn? Confirm whether duplicate-auth *immediately*
  supersedes the old connection or only after timeout.

## Code-confirmed behavior (2026-07-10)

The open question is answered: **duplicate-auth does NOT close the old conn.**
`ConnectionRegistry::insert()` (`relay/src/peers/connections.rs:55-79`) just
*pushes* a new `ConnectionEntry` onto the `Vec` for the `(peer, room)` key —
it sets `superseded_existing: existing_count > 0` as a *flag* but does **not**
remove or close the prior conn's `tx`. The old (half-open) conn stays in the
`Vec` until its own socket times out (ping timeout) and `remove()` runs.

Consequences for forwarding (`send_to_room`, `connections.rs:111-131`):
- It iterates **every** entry in the `Vec` and sends to each (skip only the
  originator's `conn_id`). So while both conns exist, **both receive a copy**
  of every forwarded frame — including the half-open one whose `tx.send()`
  will eventually fail (buffered `mpsc::UnboundedSender` — see
  `gate-security-unbounded-outbound-queues`).
- `peer_offline` fires only on the N→0 transition (`registry.rs:51-53`), so it
  does NOT fire on duplicate-auth — the extension never learns the *old* conn
  is being replaced, only that the peer is still online (correctly).

So the design decision reduces to: **should `insert()` actively close the old
conn(s) at the same key when a duplicate authenticates?** That would make
recovery immediate (no ping-timeout window) and stop the half-open conn from
receiving (and buffering) forwarded frames. The `superseded_existing` flag
already identifies the case; the missing step is closing the prior `tx`(s).
This is a small, well-scoped relay change — not a wire change, not an app
change. The risk is closing a conn that's mid-receive on a legitimate
multi-device owner (two phones, same key) — but `send_to_room` already
fan-outs to all, so closing the old one only matters for the half-open case,
and a legitimate second device would not expect the first to be killed.
Needs that multi-device-owner check before implementing.

## References

- `relay/src/handlers/peer.rs:123` — 25 s WS keepalive ping.
- `relay/src/peers/registry.rs` — duplicate-connection / last-conn-wins
  handling (`room_ended`, `peer_offline` semantics on last duplicate
  disconnect).
- Relay logs: `authenticated` at `18:07:17` with no preceding `disconnected`
  for the prior local conn.
- `idea-mobile-drop-slow-recovery`, `idea-extension-pumps-into-dead-app-peer`.

## Implementation plan

The change is in `relay/src/peers/connections.rs` — the `insert()` path. Today
it pushes a new `ConnectionEntry` and returns; it does not touch prior entries.
The fix closes the prior conn(s) at the same key when `superseded_existing`
would be true.

1. **Close prior `tx`(s) on duplicate auth.** In `insert()`, when
   `existing_count > 0`, drop the prior entries from the `Vec` **and** close
   their `tx` channels (drop the `UnboundedSender` so the receiver task ends
   and the socket is torn down, not just the registry entry). Returning the
   closed `conn_id`s in `ConnectionInsert` lets the caller log / emit a
   `peer_offline`-style transition if useful (but see the multi-device check
   below before wiring any broadcast).
2. **Decide `send_to_room` behavior during the (now-closed) window.** With the
   old conn closed synchronously inside `insert()`, there is no window where
   both conns receive — so no fan-out-to-half-open behavior. Confirm
   `send_to_room`'s `skip_conn_id` logic still routes only to the new conn.
3. **Multi-device-owner check (the one risk).** Two phones sharing one key is
   a legitimate, supported case (`registry.rs:355` test
   `duplicate_room_accepted_and_broadcast` enshrines it). Confirm whether the
   duplicate-auth-at-same-key case is *always* a half-open reconnect (safe to
   close) or can be a genuine second device. If the latter, closing the old
   conn would kill the first device's session — unacceptable. **Resolution
   options:** (a) only close when the new conn comes from the same source IP
   as the existing one (a reconnect, not a second device); (b) only close
   when there is exactly one existing conn at the key and it has been silent
   (no recent ack) — heuristic; (c) keep current behavior and accept the
   ping-timeout window as the cost of supporting multi-device. **Pick (a) if
   the source-IP is available at auth time** — it's the cleanest discriminator
   and matches the observed symptom (same peer, different network = reconnect).
   If source-IP is not available at `insert()`, fall back to (c) and document.
4. **Tests.** Add to `relay/src/peers/registry.rs` tests:
   - duplicate auth at the same key closes the prior conn's `tx` (sender
     `is_closed()` / receiver ends);
   - `send_to_room` after duplicate auth routes only to the new conn;
   - the multi-device-owner case (two conns, different source IP if (a) is
     chosen) does NOT close the first conn;
   - `peer_offline` / `room_ended` semantics unchanged when the last conn
     disconnects normally.

## Acceptance Criteria

- [ ] A duplicate auth at the same `(peer, room)` key closes the prior
  conn's `tx` (the old socket is torn down, not just the registry entry).
- [ ] After duplicate auth, `send_to_room` routes only to the new conn (no
  fan-out to the half-open one).
- [ ] The multi-device-owner case (two devices, same key) is NOT broken —
  the first device's conn is not killed by the second's auth (per the
  resolution chosen in implementation step 3).
- [ ] `peer_offline` / `room_ended` semantics on normal last-conn disconnect
  are unchanged.
- [ ] `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green.
- [ ] No wire change (`PROTOCOL.md` untouched), no app change, no
  pi-extension change.

## Out of scope

- Shortening the 25 s ping interval (separate tuning concern).
- An app-side "I'm replacing my connection" signal (not needed if the relay
  closes on duplicate auth; would be a wire change).
- The unbounded-outbound-queue hardening (`gate-security-unbounded-outbound-queues`)
  — this fix *reduces* the window that feeds it but does not bound the queue
  itself; that gate item remains independently valid.
