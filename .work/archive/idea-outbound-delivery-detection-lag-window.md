---
id: idea-outbound-delivery-detection-lag-window
created: 2026-07-09
updated: 2026-08-26
tags: [pi-extension, relay, app, bug, lifecycle]
status: superseded
superseded_by: app-side auto-session_sync on reconnect implemented (SyncService._onlineActivated → requestSync(), sync_service.dart:1001; ChatViewModel fresh-online edge) — the item's chosen closure option; groom 2026-08-26
---

# Outbound delivery gap during the peer_offline detection-lag window

## Observed (live, 2026-07-09)

Relay log showed ~18 frames dropped for the app peer (`dest=dpOPIdc= room=main`)
between `14:34:35` and `14:34:36`, while the app only re-authenticated at
`14:34:43` — an **8-second window** where the relay had no route to the app
but the extension didn't yet know the peer was gone (no `peer_offline` had
arrived). The extension kept handing frames to the relay for forwarding to a
peer that no longer existed; the relay dropped each with
`WARN dest (peer, room) not found, dropping`.

This is the window that `feature-outbound-buffer-on-peer-offline` (scoped
2026-07-09) **does not cover** — that feature only buffers once the extension
*knows* the peer is offline (after `peer_offline` arrives). The detection-lag
window is the gap *before* that signal.

## Why it's a separate, larger piece

Closing this window requires state that currently lives nowhere:

- **Relay-side hold** — the relay would need to buffer frames for a briefly-
  absent `(peer, room)` and flush on the peer's re-auth. This conflicts with
  the relay's current "opaque forwarder, holds no per-peer data-plane state"
  posture, and intersects `gate-security-unbounded-outbound-queues` (any such
  buffer must be bounded). It's a relay semantics change, not a tweak.
- **OR app-side auto-`session_sync` on reconnect** — the app pulls missed
  transcript history on every `StatusOnline` transition. Today
  `ConnectionManager.requestResumeHydration()` only rehydrates presence +
  rooms, not transcript. This would make the detection-lag loss recoverable
  without relay state, but it's an app change and a `session_sync`-load
  consideration.

Either path is wire-bearing or component-bearing enough to warrant its own
design pass — likely an **epic** with a `PROTOCOL.md` delivery-guarantee
roll-forward (the protocol currently only documents inbound queued-message
semantics; outbound delivery guarantees are unspecified).

## Relationship to tracked work

- `feature-outbound-buffer-on-peer-offline` (active, drafting) — closes the
  **known-offline** window. Ships first; reduces the detection-lag window's
  blast radius (fewer frames hit it once observed-offline peers buffer).
- `idea-extension-pumps-into-dead-app-peer` (backlog) — the symptom record for
  the same live drop; its open question ("does the extension get a
  `peer_offline` signal?") is now **resolved: yes** (`index.ts:331-342`).
- `gate-security-unbounded-outbound-queues` (backlog, medium) — any relay-side
  buffer added here must be bounded or it feeds this gate.
- `feature-session-stable-message-delivery` (active, implementing) — the
  *inbound* delivery guarantee; the outbound detection-lag fix is the
  outbound counterpart to the same resilience theme.

## Followup at scope time

When promoted: decide relay-hold vs app-auto-sync (or both) as the primary
direction — that's the strategic fork that determines epic vs feature and
whether `PROTOCOL.md` gains an outbound delivery-guarantee section. Consider
whether app-auto-`session_sync`-on-reconnect alone (the smaller of the two)
suffices as a first cut, making the relay-hold path unnecessary.
