---
id: idea-offline-state-liveness-ux
created: 2026-08-27
updated: 2026-08-27
tags: [app, ux, bug]
---

# Offline state must look alive — retry liveness + unreachable-cause hint

Field evidence (capture 2026-08-27T22-34: 15 minutes of continuous
connect-failures at 30s backoff — phone-side tailnet/VPN drop — read by the
operator as "app stuck offline until force-close"). Behavior was CORRECT
(retry ladder never stopped; self-recovered at 22:32:37 the moment the path
returned) but experientially dead: an undifferentiated offline banner for
minutes looks identical to a wedged app.

## Work

- After N consecutive failed connect attempts: surface liveness —
  last-attempt timestamp + next-retry countdown in the connection status
  surface.
- After N consecutive WebSocketChannelException (TCP-level) failures
  specifically: add the pointed hint — "Can't reach the relay — check
  Tailscale/VPN" (distinguish transport-unreachable from
  relay-rejecting/auth failures, which should hint differently).
- Consider a manual "retry now" affordance in the same surface.

Not a correctness blocker; the reconnect machinery is proven sound
(capture: re-arm intact through 3h churn incl. extension restart).
