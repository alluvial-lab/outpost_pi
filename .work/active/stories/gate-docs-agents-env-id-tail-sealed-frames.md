---
id: gate-docs-agents-env-id-tail-sealed-frames
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# AGENTS claims owner-message IDs correlate through the relay's cross-PC env_id_tail

## Drift category
foundation-doc-assertion

## Location
- Doc: `AGENTS.md:127-130,139-144`
- Contradicting source: `relay/src/handlers/pi_forward.rs:357-361; PROTOCOL.md:461-467`

## Current doc text
> env_id_tail — the cross-side correlation key that joins the phone's msg-send id and the extension's app user_message id.

## Contradiction
env_id_tail is taken from a cross-PC pi_envelope ID. Owner-message IDs now live inside AEAD-sealed outer.ct, so the relay cannot extract or correlate the phone's inner message ID.

## Required edit
Separate owner-channel app↔extension ID correlation from cross-PC relay-envelope correlation; do not claim a relay-side join for sealed owner frames.
