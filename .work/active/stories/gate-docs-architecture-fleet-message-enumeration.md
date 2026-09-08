---
id: gate-docs-architecture-fleet-message-enumeration
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: docs
created: 2026-09-07
updated: 2026-09-07
---

# Architecture wire-union lists omit fleet update messages

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:166-178`
- Contradicting source: `protocol/schema/app-pi-client.schema.json:149-152,258`; `protocol/schema/app-pi-server.schema.json:292-294,448`

## Current doc text
> `ClientMessage` (app → pi) union: `pair_request`, `user_message` (with
> optional `images` and `streaming_behavior`), `queued_message_set` /
> `queued_message_clear`, `approve_tool`, `cancel`, `ping`, `session_sync`, and
> typed actions `session_new` / `session_compact` / `model_set` /
> `thinking_set` / `list_models`, plus the capture-upload sequence...
>
> `ServerMessage` (pi → app) union: ... `action_ok` / `action_error` /
> `models_list` / `compaction` and capture-upload replies...

## Contradiction
The architecture describes these as the current complete `ClientMessage` and `ServerMessage` unions but omits the additive `fleet_update` client command and `fleet_update_status` server event that the generated schema and registries now carry.

## Required edit
Roll both union descriptions forward to include `fleet_update` and `fleet_update_status`, respectively. Keep the generated-schema provenance statement true for every listed variant and do not add historical or versioned prose.
