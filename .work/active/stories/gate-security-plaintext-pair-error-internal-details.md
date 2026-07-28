---
id: gate-security-plaintext-pair-error-internal-details
kind: story
stage: implementing
tags: [security, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-24
updated: 2026-07-28
---

# Plaintext pairing errors expose raw internal failures to the relay

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Low → parked per gate_finding_routing.

## Domain
Error Handling & Logging

## Location
`pi-extension/src/extension/owner_multiplexer.ts:450`

## Evidence
Failure while deriving or persisting channel state is returned in the pre-key pair_error as `${String(err)}`. Pairing responses remain plaintext inside the relay-visible outer envelope. A relay observing a legitimate pairing failure can receive filesystem, keyring, or platform error details, including possible local paths.

## Remediation direction
Send a fixed internal_error message on the wire and retain only a content-free local category or normalized error class.
