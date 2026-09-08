---
id: gate-docs-pi-extension-skill-fleet-messages
created: 2026-09-07
updated: 2026-09-07
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Pi extension skill omits fleet update protocol messages

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/pi-extension-typescript/SKILL.md:218-219`
- Contradicting source: `protocol/schema/app-pi-client.schema.json:149-152,258`; `protocol/schema/app-pi-server.schema.json:292-294,448`

## Current doc text
> Client/app messages: ... `session_new`, `session_compact`, `model_set`,
> `thinking_set`, `list_models`, and the capture-upload control sequence...
>
> Server/extension messages: ... `action_ok`, `action_error`, `models_list`,
> and the capture-upload replies...

## Contradiction
The stack reference enumerates the protocol families but omits the shipped `fleet_update` client message and `fleet_update_status` server event. Agents using this reference can miss the Fleet settings/coordinator message path even though the generated schema and runtime now support it.

## Required edit
Extend both protocol-family lists with `fleet_update` and `fleet_update_status`, and briefly identify the latter as a repeated status event rather than an action reply. Keep the schema-generated protocol as the source of truth.
