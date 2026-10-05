---
id: idea-wake-provenance-threading
created: 2026-10-05
updated: 2026-10-05
tags: [pi-extension, workflow]
---

# Wake provenance threading through the delivery path

Parked from gate-security v0.13.0 (medium routing). The local/remote wake
decision currently derives from the canonical parseAddress at the consumer
(mcp/wake.ts) plus strict `_relay` ingress validation (broker_remote.ts) —
fail-closed, but still address-text-derived at the MCP layer.

The structurally strongest form: thread explicit provenance from where it
is known — BrokerRemote.handleIncoming (sibling-validated or `_relay`)
marks envelopes at broker injection, the SessionPeer/MeshNode onMessage
callback carries `{origin: "local" | "remote"}` through to consumers, and
the wake coordinator authorizes from that flag. Removes the residual
fail-closed availability edge (local names containing literal colons never
wake) and the reliance on the `_relay` string.

Trigger to pick up: any future session-layer envelope-metadata work, or if
a local peer legitimately needs a colon-bearing name with wake.
