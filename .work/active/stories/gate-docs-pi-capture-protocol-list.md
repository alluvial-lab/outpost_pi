---
id: gate-docs-pi-capture-protocol-list
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-25
---

# Pi extension skill protocol lists omit capture-upload messages

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/pi-extension-typescript/SKILL.md:204-207`
- Contradicting source: `protocol/schema/app-pi-client.schema.json:16-18,143-145` and `protocol/schema/app-pi-server.schema.json:26-27,321-322`

## Current doc text
> Client/app messages: `pair_request`, `user_message`, ... `list_models`.
> Server/extension messages: `pair_ok`, ... `models_list`.

## Contradiction
The skill's protocol-family lists are presented as the message vocabulary but
omit the shipped `capture_upload_begin` / `capture_upload_chunk` /
`capture_upload_end` client messages and `capture_upload_ack` /
`capture_upload_error` server messages.

## Required edit
Extend the protocol-family lists and nearby handler/source references with the
capture-upload family, including its control-family semantics and generated
limits, so the skill describes the current extension surface.

## Implementation

Documented the capture-upload control sequence, handler wiring, generated 8 KiB/2 MiB/one-in-flight limits, and typed replies in `.agents/skills/pi-extension-typescript/SKILL.md`.
