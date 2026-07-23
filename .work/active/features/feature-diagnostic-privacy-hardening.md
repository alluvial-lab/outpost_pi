---
id: feature-diagnostic-privacy-hardening
kind: feature
stage: drafting
tags: [security, cockpit, app]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-23
updated: 2026-07-23
---

# Diagnostic-privacy hardening (round 2)

## Brief

Follow-up cluster to 0.2.0's `feature-redact-secrets-from-diagnostic-surfaces`.
The 2026-07-23 groom verified these five findings are **not** superseded by
the shipped redaction work — live code still leaks raw diagnostic content into
logs, traces, and retained events:

1. `gate-security-cockpit-temp-workspace-trace` — temp workspace's absolute
   path in traces.
2. `gate-security-formatter-reload-diagnostics-path-disclosure` — raw file
   exception and full stack trace in diagnostics.
3. `gate-security-lsp-stderr-logged` — LSP stderr lines logged verbatim.
4. `gate-security-mobile-failure-detail-logged` — mobile failure detail
   written verbatim into a persistent exportable `MsgFailedEvent`.
5. `gate-security-rpcunknown-retains-wire-discriminator` — unknown-RPC
   handling retains arbitrary wire discriminator text.

Each finding carries severity/location/evidence/remediation in its child
story. The design pass should establish one shared diagnostic-redaction
policy (what may be logged verbatim, what is hashed/truncated, what is
redacted) rather than five point fixes — that policy is the feature's real
deliverable; the child stories are its applications.

## Simplification opportunity

A single redaction helper/policy module per subproject (extending the 0.2.0
`feature-redact-secrets-from-diagnostic-surfaces` seams) replaces per-callsite
ad-hoc redaction and gives future diagnostics a default-safe path.

## Origin

Groom 2026-07-23, cluster F6 — promoted per advisor-review recommendation
that diagnostic-privacy follow-ups pair with v0.3.0 hardening.
