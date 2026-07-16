---
kind: story
release_binding: null
parent: feature-mobile-tui-parity-chat-resilience
stage: drafting
id: idea-mobile-outgoing-message-swallowed
created: 2026-07-02
updated: 2026-07-02
tags: [app, pi-extension, relay, bug]
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
