---
id: backlog-app-reconnect-churn-timeout-lifecycle-failures
created: 2026-08-21
updated: 2026-08-21
tags: [app, relay, bug]
---

# Random disconnects/reconnects in-chat: 89 timeout lifecycle failures over 4 days

Operator report (2026-08-21) + capture `cad-11f1-b349` evidence: 336
connStatus transitions, 46 connChannelLost, lifecycleFailure ×100
(89 TimeoutException, 11 WebSocketChannelException) across the 4-day ring.
Observed pattern: preauth → channelLost ~6s later → retrying → online
~5-6s — i.e. periodic brief drops, not network-wide outages (envelopes
flow between drops).

## Work

- Attribute the TimeoutException source (heartbeat interval vs socket
  read/idle timeout mismatch is the prime suspect — relay heartbeat
  first-tick had a v0.4.0 fix; check the app-side keepalive math).
- The observability arc's reconnect attribution should name the cause per
  drop; if it already does, decode that field from the captures and skip
  straight to the fix.
- Cross-check relay logs at the same timestamps (wire-side close vs
  client-side timeout).
