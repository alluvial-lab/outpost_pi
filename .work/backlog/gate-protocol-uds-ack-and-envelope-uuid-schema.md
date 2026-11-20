---
id: gate-protocol-uds-ack-and-envelope-uuid-schema
created: 2026-11-20
updated: 2026-11-20
tags: [pi-extension, docs]
---

# Consolidate local UDS ACK types, document IPC island, and add UUID format to `agent-envelope.schema.json`

Parked from `v0.14.0` release-gate `protocol-contract` scan (medium/low, non-blocking).

## Evidence pointers

- Local UDS broker IPC control/ACK types (`RegisterMsg`, `RegisterAck`, `SystemBody`, `AckBody`) are duplicated across `pi-extension/src/session/broker.ts:168-209` and `pi-extension/src/session/peer.ts:67-82`, and ACK status strings are independently re-enumerated in `pi-extension/src/session/tools.ts:29, 285-312` and `pi-extension/src/mcp/mesh_server.ts:247-268`. Extract a single shared local UDS ACK registry/formatter and add a durable island note explaining why Node-only local UDS IPC stays outside `protocol/schema/manifest.json`.
- `protocol/schema/defs/agent-envelope.schema.json:23-29` still specifies `id` and `re` as `"type": "string", "minLength": 1` (with only non-enforced `x-outpost-pi.idSemantics`), whereas `pi-extension/src/session/envelope.ts:15-18, 92-98` enforces `UUID_RE` on the wire. Add a UUID pattern constraint to the schema and regenerate `protocol.generated.ts` so generated cross-PC validators match.
