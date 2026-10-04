---
id: idea-mesh-body-double-serialization
created: 2026-10-03
updated: 2026-10-03
tags: []
---

Pi→Claude mesh bodies arrive double-serialized at the MCP inbox.

During the live launcher smoke (story
`story-claude-launcher-safe-local-qualification`, 2026-10-03), a `agent_send`
body sent as a JSON **object** by the Pi runtime arrived at the Claude MCP
inbox as a JSON-encoded **string** — the smoke Claude reported: "The body came
through as a JSON-encoded string, not a JSON object … serialized twice
somewhere." Pi→Pi traffic in the same session preserved object bodies
(nextup's requirements object rendered as an object in the Pi turn input).

Legal per the envelope contract (body is free-form) and parseable, so it was
recorded as an observation, not a blocker. Worth investigating if structured
bodies matter to mesh consumers: the extra stringification lives somewhere on
the Pi send path (native `agent_send` tool → envelope) versus
`pi-extension/src/mcp/mesh_server.ts`'s inbox, which renders whatever body it
receives via `JSON.stringify`.
