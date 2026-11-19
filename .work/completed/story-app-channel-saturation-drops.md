---
id: story-app-channel-saturation-drops
kind: story
completed: 2026-11-15
tags: [relay, app, bug]
created: 2026-11-15
updated: 2026-11-15
---

# App↔relay channel drops: distinguishable outbound-mailbox saturation close

Completed (`fa32d6abb`). Made relay outbound-mailbox saturation closures distinguishable from generic protocol failures by emitting a dedicated WebSocket close (`1013` + saturation reason) on the relay and projecting exact `1013`+reason into `serverCloseFrame` / `transportBackpressure` diagnostics in the Flutter app, with `PROTOCOL.md` updated and relay (240 tests) + app (`flutter analyze`, 1079 tests) verified green. Full pre-migration story record preserved in Git history at `fa32d6abb`.
