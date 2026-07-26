---
id: app-relay-url-network-failover
created: 2026-07-26
updated: 2026-07-26
tags: [app, bug]
---

# Single relay URL leaves the app fully down when its network path dies

Surfaced 2026-07-26 (phone dual-homing incident): the app holds exactly one
relay URL. When that URL's reachability is network-dependent (tailnet IP
with the tunnel down, LAN IP while remote), the app enters an infinite
connect/retry loop with zero relay-side attempts and no user-facing
explanation of WHY. From the user's seat the relay is just "offline".

Two angles:

1. **Diagnostics (small)**: the connect loop cannot distinguish DNS/route
   failure (address unroutable — likely wrong network/tunnel) from relay
   refusal. Surface "relay unreachable — check network/VPN" after N
   consecutive transport timeouts vs a real relay error, so users aren't
   debugging blind. The debug capture already records attempt counts; the UI
   does not act on them.
2. **Failover (larger, mobile-remote-coding checklist)**: support an
   ordered set of relay addresses (e.g. tailnet, LAN) probed per connect
   attempt, or canonical-address re-discovery via the pairing record. The
   pairing QR embeds one URL; the app could learn alternates.

Context: tailscale split-tunnel deployment (2026-07-26) made the relay
address tailnet-canonical; relay logs + app debug captures from the
incident are in debug/ (90b/914/935 series).
