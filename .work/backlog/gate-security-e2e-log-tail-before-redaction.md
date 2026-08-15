---
id: gate-security-e2e-log-tail-before-redaction
created: 2026-08-15
updated: 2026-08-15
tags: [workflow, security]
---

# E2E failure path prints raw Pi-host logs before enforcing the redaction result

Post-hoc v0.5.0 security-gate finding. Severity: Low.

## Location
`e2e/run-pairing.sh:125` — on dual failure, `tail -120 "$PI_HOST_LOG" >&2`
runs before the redaction status is enforced.

## Work
Enforce the redaction result before emitting diagnostics; print only
allow-listed structured fields rather than an unfiltered log tail.
