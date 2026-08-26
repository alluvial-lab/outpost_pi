---
id: app-relay-url-network-failover
kind: story
stage: implementing
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-26
updated: 2026-08-27
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

## Implementation notes
- Execution capability: inline, focused relay endpoint resolution and reconnect adapter change.
- Review weight: standard (source: caller default).
- Files changed: `app/lib/data/transport/relay_config.dart`, `app/lib/config/dependencies.dart`, and `app/test/data/transport/relay_config_test.dart`.
- Tests added/removed: Added deterministic candidate ordering/deduplication tests; the production reconnect factory tries the configured relay first and the retained pairing-record endpoint second, with per-candidate cancellation.
- Simplification: No new persistent preference schema or parallel connection race was introduced; the existing pairing record supplies the alternate.
- Discrepancies from design: The larger multi-address preference editor and explicit transport-error copy remain deferred; this slice provides the ordered failover path requested by the story.
- Adjacent issues parked: none.

## Blocker
- The required full app verification command is still blocked by the unrelated `PairingPage` widget-test timeout observed during the story-1 run; the focused relay configuration suite and scoped analyze pass. The story remains `stage: implementing` until the full suite is green.
