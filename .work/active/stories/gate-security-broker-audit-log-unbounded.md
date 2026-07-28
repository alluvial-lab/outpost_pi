---
id: gate-security-broker-audit-log-unbounded
kind: story
stage: review
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-28
---

# Local mesh audit log grows without a retention bound

## Severity
Medium

## Domain
Error Handling & Logging / Resource Exhaustion

## Relevance
Release-relevant

## Location
`pi-extension/src/session/broker.ts:562`

## Evidence
```ts
if (!this.auditPath) return;
const line = JSON.stringify({
  ts: Date.now(), from: env.from, to: env.to, id: env.id,
...
await appendFile(this.auditPath, line, "utf8");
```

## Issue
Every normally configured local mesh broker receives an `auditPath`, and every routed envelope calls `_appendAudit` (`pi-extension/src/session/broker.ts:459`). The file at `~/.pi/remote/sessions/local/audit.jsonl` is append-only with no size cap, rotation, age retention, or startup sweep. A malfunctioning or hostile local or authorized cross-PC mesh participant can therefore consume disk indefinitely by routing valid envelopes; long-lived normal use also grows the file across reboots. The record is metadata-only, but attacker-controlled recipient arrays and addresses still affect record size. Exploitation requires mesh access, so this is a bounded-trust resource-exhaustion issue rather than an unauthenticated remote blocker.

## Remediation direction
Give the audit writer an explicit byte/record budget and bounded rotation/retention policy, preserving recent correlation metadata while deleting or rotating old segments. Clamp variable-cardinality fields such as recipient lists in the diagnostic projection, keep payload bodies excluded, and add a deterministic test proving sustained routes cannot grow retained audit storage beyond the configured ceiling.

## Implementation notes

- Serialized audit writes, clamps diagnostic fields/recipient projections, and
  rotates a 256 KiB active log into one 256 KiB retained predecessor.
- Added sustained-route coverage proving active and retained audit segments
  remain within the concrete ceiling.
- Changed `pi-extension/src/session/broker.ts` and `src/session/e2e.test.ts`.
- Verified with `vitest run src/session/e2e.test.ts` (33 tests) and
  `tsc --noEmit`.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
