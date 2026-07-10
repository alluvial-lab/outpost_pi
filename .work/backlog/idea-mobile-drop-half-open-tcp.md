---
id: idea-mobile-drop-half-open-tcp
created: 2026-07-02
updated: 2026-07-10
tags: [app, relay, bug, lifecycle]
---

# Mobile network switch: no clean disconnect, half-open TCP window

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

## Followup at design time

Questions to resolve:
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
