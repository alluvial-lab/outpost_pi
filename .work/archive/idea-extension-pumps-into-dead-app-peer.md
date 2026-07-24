---
id: idea-extension-pumps-into-dead-app-peer
status: superseded
superseded_by: story-extension-suspend-fanout-on-peer-offline
created: 2026-07-02
updated: 2026-07-24
stage: done
release_binding: v0.3.0
tags: [pi-extension, relay, bug, lifecycle]
---

# Pi-extension keeps streaming at a dead app peer after disconnect

## Observed (live drop test, 2026-07-02)

During a mobile network-drop test, the app's relay connection dropped at
`18:02:01Z` (relay logged `disconnected peer=/uV6O0I= room=main`). The
pi-extension (peer id `YqWjpYw=`) kept streaming transcript frames at the
now-gone app peer for ~2 minutes (until ~`18:03:49Z`). The relay correctly
dropped each frame and logged a WARN per frame:

```
WARN relay::handlers::connection_actor: dest (peer, room) not found, dropping
   from=YqWjpYw= dest=/uV6O0I= room=main bytes=200   (× dozens/sec)
```

So the relay *knew* the app was gone, but the extension evidently didn't — its
own leg to the relay was healthy, so it kept handing transcript frames to the
relay for forwarding to a peer that no longer existed. The flood only stopped
because the turn ended (nothing left to pump), not because the extension
learned the app was gone.

## Suspected gap

The `peer_offline` type exists in the generated protocol
(`pi-extension/src/protocol/generated/protocol.generated.ts`) but no consumer
was found on the extension side during this session — the extension's
`onDisconnect` path (`_onPeerDisconnect` → `ownerHarness.disconnectOwner`) is
wired, but whether the relay actually emits `peer_offline` to the extension
(or whether the extension consumes it) was NOT confirmed. That's the open
question: **is there a working "app peer went away" signal reaching the
extension, or does it rely entirely on the app reconnecting via
`session_sync`?**

## Impact

- Wasted work + log spam: the extension streams a full turn's worth of frames
  into a void, and the relay logs every dropped frame as WARN.
- The transcript the app eventually rehydrates via `session_sync` is
  recorded server-side regardless (transcript event log), so no data loss —
  but the extension burns CPU/IO pumping a dead channel for the whole turn.
- Compound effect with slow reconnect (see `idea-mobile-drop-slow-recovery`):
  the longer the app is gone, the longer the extension pumps into the void.

## References

- `pi-extension/src/index.ts` — `_onPeerDisconnect`, `_disconnectOwnerForRuntime`,
  `_routeClientMessageFrom`.
- `pi-extension/src/extension/relay_transport.ts` — `createPeerChannel`
  wires `onDisconnect`, but unclear what upstream signal triggers it.
- `pi-extension/src/protocol/generated/protocol.generated.ts` — `peer_offline`
  type exists; consumer not located.
- Relay drop log: `WARN relay::handlers::connection_actor: dest (peer, room)
  not found, dropping` (relay side, confirmed emitting).

## Followup at design time

Confirm whether the relay emits `peer_offline` (or equivalent) to the extension
on app socket close, and whether the extension handles it. If not, the fix is
to surface app-peer-gone to the extension so it stops (or suspends) its
outbound fan-out for that owner instead of pumping until turn end.

Distinct from `idea-mobile-drop-slow-recovery` (recovery latency) — this one
is about wasted work during the dead window.

## Resolution (2026-07-09)

The open question is **answered: yes, the signal reaches the extension.**
`peer_offline` / `peer_online` are consumed at `pi-extension/src/index.ts:331-342`
→ `OwnerMultiplexer.markPeerOffline` / `markPeerOnline`
(`owner_multiplexer.ts:432-443`), and fan-out *is* suspended for a known-offline
peer (`broadcast()` at `:450` skips `offlinePeerIds`).

So the "pumps into a dead peer" symptom is narrower than originally thought:
the extension suspends correctly **once it knows** the peer is gone. The
remaining gap is the **detection-lag window** — frames sent *before*
`peer_offline` arrives (the relay already has no route, the extension hasn't
been told). That window is now tracked at
`idea-outbound-delivery-detection-lag-window` (backlog), and the
known-offline buffering counterpart is scoped as
`feature-outbound-buffer-on-peer-offline` (active, drafting).

This item is retained as the symptom record; no separate promotion needed —
the two child items above cover both windows.
