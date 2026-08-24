---
id: idea-mobile-outgoing-message-swallowed
kind: story
stage: done
tags: [app, pi-extension, relay, bug]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-18
---

# Mobile: outgoing user message swallowed (not delivered, not surfaced)

## Observed (live drop test, 2026-07-02)

During the mobile network-drop test (local wifi → 5g/wireguard), the operator
reported that one outgoing message from the mobile chat was "swallowed" — it
did not appear to reach the pi session (no agent response to it), but the
operator still saw the agent's *responses* (to other inputs) on the app. So
the receive path was working but a specific outgoing message vanished without
any user-facing error.

This is **not yet reproduced server-side.** It was not visible in the relay
logs reviewed during the session — the relay showed the app's
`authenticated` reconnects and the WARN flood from the extension pumping into
the dead peer, but no specific evidence of a dropped user_message envelope.

## Why it matters

A swallowed message is worse than a visible error: the user believes the
message was sent, gets no failure signal, and only later notices the agent
never saw it. Silent data loss in the user→agent direction erodes trust in
the channel.

## Possible contributors (unconfirmed)

- Message was in-flight in the app's send buffer when the network dropped;
  the app may have discarded it on disconnect instead of queuing for retry
  on reconnect.
- Optimistic-send path: app rendered the bubble and attempted send, but the
  send never reached the relay (or the extension), and no timeout/error was
  surfaced. Compare to `idea-mobile-message-duplication-send-timeout`, which
  is the *opposite* failure (duplicate + visible `send_timeout`).
- Relay `dest not found` drops were happening during this window, but those
  are extension→app direction, not app→extension. A user_message going
  app→extension should not hit that path.

## Followup at design time

- Reproduce: send a message from the app while pulling the network, then
  reconnect, and check whether (a) the relay log shows the envelope, (b) the
  extension received it, (c) the app surfaced any error.
- Inspect the app's send path: is there a retry/queue for messages that fail
  to send during a network transition, or are they dropped on the floor?
- Inspect whether the app distinguishes "send failed" from "send
  unconfirmed" — a swallowed message suggests neither path fired.

## References

- Related but distinct: `idea-mobile-message-duplication-send-timeout` — that
  bug duplicates + shows `send_timeout`; this one silently drops with no
  signal. Opposite failure modes of the same send-confirmation surface.
- `idea-extension-pumps-into-dead-app-peer` — the dead-window during which
  this likely occurred.
- `idea-mobile-drop-slow-recovery` — the ~5 min recovery window.

## Design

**Disposition: parked live-repro.** Silent loss during a network transition is
not confidently the same defect as the reproducible navigation-time
send-confirmation bug.

## Parked

Live-repro-only; leave at `stage: drafting`. Route to
`feature-reconnect-reproduction` on the next physical drop test. Correlate the
app `msg-send` ID with relay `env_id_tail` and extension `app user_message id`
to locate the loss before choosing retry, queue, or error-surface semantics. If
the trace instead reproduces the normal-navigation timeout/duplication path,
link it to `idea-mobile-message-duplication-send-timeout`; do not add an offline
send queue speculatively.

## Retirement (2026-07-28)

Closed/archived with parent epic `epic-targeting-and-session-lifecycle-contracts`.
The observability unlock shipped; this bug was either resolved by it,
re-investigated with its original mechanism disproven, or left unreproduced
with instrumentation in place and no recurrence in 3+ weeks. See the epic's
retirement note for the full disposition.
