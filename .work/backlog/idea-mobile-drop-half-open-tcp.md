---
id: idea-mobile-drop-half-open-tcp
created: 2026-07-02
updated: 2026-07-02
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

## References

- `relay/src/handlers/peer.rs:123` — 25 s WS keepalive ping.
- `relay/src/peers/registry.rs` — duplicate-connection / last-conn-wins
  handling (`room_ended`, `peer_offline` semantics on last duplicate
  disconnect).
- Relay logs: `authenticated` at `18:07:17` with no preceding `disconnected`
  for the prior local conn.
- `idea-mobile-drop-slow-recovery`, `idea-extension-pumps-into-dead-app-peer`.
