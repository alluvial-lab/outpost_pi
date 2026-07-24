---
id: gate-docs-rust-relay-skill-plaintext-model
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Rust relay skill still teaches the pre-v0.3 plaintext trust model

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/rust-relay/SKILL.md:42,154,164`
- Contradicting source: `relay/CLAUDE.md:41-44`

## Current doc text
> The relay operator can read current plaintext envelope contents; do not claim E2E in relay docs or copy unless the protocol changes.

## Contradiction
The protocol changed. Owner-channel payloads are ciphertext opaque to the relay; only cross-PC payloads remain relay-readable.

## Required edit
Roll the responsibility, anti-pattern, and review-checklist wording forward to distinguish endpoint-provided owner E2E from unprotected cross-PC traffic.

## Implementation notes

Updated relay agent guidance to distinguish opaque paired owner-channel `ct` from relay-readable cross-PC envelopes and visible metadata.
