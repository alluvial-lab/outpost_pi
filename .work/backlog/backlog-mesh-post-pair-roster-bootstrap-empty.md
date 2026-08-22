---
id: backlog-mesh-post-pair-roster-bootstrap-empty
created: 2026-08-22
updated: 2026-08-22
tags: [pi-extension, bug, testing]
---

# Cross-PC roster does not bootstrap after post-start mesh publication

The live two-Pi lane paired one Owner to both already-connected Pi hosts,
published the two-member signed mesh blob successfully, and forced signed
membership refreshes on both hosts. Both `MeshNode` instances reported an
active relay bridge, but the broker's remote `peers_detailed` roster remained
empty on both sides for 60 seconds. An earlier probe of the legacy `peers`
projection returned only the local/self entry, not the sibling's canonical
address.

Capture and triage evidence: `.work/session-notes/live-mesh-20260822/` contains
the device capture, both pi-host logs, relay log, and Flutter failure output.
The bounded failure state was `bridgeA=true bridgeB=true peersA=0 peersB=0`.
The relay log confirms both distinct Pi identities/rooms were authenticated.

Triage direction: inspect the `setSiblings` → `rooms_check` →
`peers_request`/`peers_update` bootstrap after membership arrives later than
bridge attachment. The periodic two-minute reannounce may eventually mask the
fault, but the documented bootstrap path should populate immediately. The E2E
adapter skip-links the roster assertion and routes its scenario envelopes below
that cache using verified signed membership plus the destination's broker-issued
local address. Relay authorization, destination anti-spoofing, local broker
injection, mesh-ingress queueing, and app owner-channel visibility remain on
production paths.
