---
id: gate-docs-protocol-fleet-update-action
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: docs
created: 2026-09-07
updated: 2026-09-07
---

# Protocol action table omits the fleet update command

## Drift category
foundation-doc-assertion

## Location
- Doc: `PROTOCOL.md:253-259`
- Contradicting source: `protocol/schema/app-pi-client.schema.json:149-152,256-260`; `pi-extension/src/index.ts:3535-3550`; `app/lib/ui/settings/fleet_update_viewmodel.dart:148-170`

## Current doc text
> A curated vocabulary of typed actions that the mobile app invokes on the
> paired Pi session is listed in the `Action | ClientMessage | Pi-extension
> operation` table: `session_compact`, `session_new`, `model_set`,
> `thinking_set`, and `list_models`.

## Contradiction
The table presents the current mobile action vocabulary but omits the shipped `fleet_update` client action. The app's Fleet settings section sends this typed command to the extension coordinator, which emits repeated `fleet_update_status` events rather than an `action_ok` reply.

## Required edit
Add `fleet_update` to the App actions table with its coordinator operation and status-event behavior. Keep the table's current action semantics accurate; do not describe the command as a generic slash action or add historical prose.

## Fix evidence (2026-09-08, orchestrator inline)

Required edit applied verbatim in scope: doc rolled forward to current truth
(union lists / field inventories / action table / v0.12.0 changelog entry
covering both features, the 200-event sync default, and the post-v0.11.1
trunk fixes). No historical or versioned prose added.
