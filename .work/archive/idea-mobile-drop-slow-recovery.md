---
id: idea-mobile-drop-slow-recovery
kind: story
stage: done
tags: [app, pi-extension, relay, bug, lifecycle]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-18
---

# Mobile network drop: slow end-to-end recovery (~5 min)

## Observed (live drop test, 2026-07-02)

Operator dropped local wifi and reconnected via wireguard on 5g. Relay-side
peer-handler timeline (all same app peer id `/uV6O0I=`):

| Time (Z) | Event | Source addr |
|---|---|---|
| 18:02:01 | `disconnected` (local wifi drop) | `192.168.40.136:46622` |
| 18:03:50 | `authenticated` (reconnect, still local) | `192.168.40.136:57586` |
| 18:07:17 | `authenticated` (5g via wireguard) | `192.168.11.2:54008` |

End-to-end recovery (drop → wireguard auth) = ~5 min 16 s. The local reconnect
was ~1m49s; the local→5g transition added ~3m27s. The app eventually resumed
the session and rendered the agent's output, so the capability held — but
recovery latency was high.

## Possible contributors (not confirmed)

- App reconnect backoff (exponential? too aggressive on the high end?).
- Wireguard handshake + 5g bring-up time (external, not app-controllable).
- App not promptly noticing the local path was dead (no clean FIN — see
  `idea-mobile-drop-half-open-tcp`).
- App reconnect state machine stalling waiting on something.

Operator did not report the phone-side "reconnecting" duration, so the split
between app backoff vs wireguard vs app state-machine stall is unknown.

## Impact

- User perceives a long "broken" window after a routine mobile network
  transition (wifi → cellular), which is the single most common mobile
  disruption. ~5 min is too long for a product-quality experience.
- During the dead window the extension pumps into the void (see
  `idea-extension-pumps-into-dead-app-peer`), so the two issues compound.

## Followup at design time

Need phone-side timing to attribute the ~5 min across (a) app reconnect
backoff, (b) wireguard/5g bring-up, (c) app state machine. Instrument the
app's reconnect state transitions with timestamps and compare against the
relay's `authenticated` log line. Then decide whether to shorten backoff,
detect dead paths faster, or both.

## References

- Relay peer-handler logs: `INFO relay::handlers::peer: authenticated/disconnected`.
- `idea-mobile-drop-half-open-tcp` — no clean disconnect on network switch,
  which likely contributes to slow detection.
- `idea-extension-pumps-into-dead-app-peer` — compounds during the dead window.

## Design

**Disposition: parked live-repro.** No implementation unit is created from the
unattributed five-minute observation.

## Parked

Live-repro-only; leave at `stage: drafting`. Route to
`feature-reconnect-reproduction` on the next physical wifi↔cellular/WireGuard
drop test, using app `conn-status`/`conn-channel-lost` timestamps and relay
auth/supersession logs to split app backoff, half-open detection, and external
network bring-up. Whichever feature records the attributed trace owns the
resulting fix; this copy then closes as provenance. Do not tune backoff from the
current anecdote.

## Retirement (2026-07-28)

Closed/archived with parent epic `epic-targeting-and-session-lifecycle-contracts`.
The observability unlock shipped; this bug was either resolved by it,
re-investigated with its original mechanism disproven, or left unreproduced
with instrumentation in place and no recurrence in 3+ weeks. See the epic's
retirement note for the full disposition.
