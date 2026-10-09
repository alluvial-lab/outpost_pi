---
id: story-re-uuid-contract
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-09
updated: 2026-10-09
---

# Enforce the `re` null-or-UUID contract: tool-layer fail-fast + loud broker drops

## Brief

The agent-network wire protocol requires an envelope's `re` to be null or a
UUID (`session/envelope.ts` `parse()`, `UUID_RE`), but the `agent_send` tool
schema advertises `re: string` with no constraint. An agent that follows the
apparent contract — e.g. the nextup two-lane convention of `re=<item-id>`
thread tokens — writes envelopes the broker's parser rejects with
`EnvelopeError`, which the receive path swallows **silently**: no ACK, no
NACK, no audit line. The sender sees an opaque 5s "transport error" timeout
indistinguishable from peer-offline. This pinned two lanes for an afternoon
(2026-10-09) before fleet diagnosis cracked it via broker-audit absence.

Two compounding defects, both fixed here:

- **D1 (API contract):** validate `re` (null-or-UUID) at the tool layer in
  BOTH send surfaces — the pi extension's `agent_send`
  (`session/tools.ts`) and the MCP's `agent_send` (`mcp/mesh_server.ts`) —
  returning an immediate parameter error that names the constraint and the
  escape hatch ("put thread tokens in the body"). Reuse `UUID_RE` from
  `envelope.ts` (single source of truth — no second regex).
- **D2 (observability):** make broker-side `EnvelopeError` drops loud —
  append an audit line for the rejected envelope and NACK the sender with a
  new ack status `invalid_envelope` (distinct from `denied`/timeout), so
  "bad envelope" is caller-visible in the tool result.

Plus one doc line: the agent-network skill (and both tool descriptions)
state explicitly that `re` accepts an incoming envelope id only.

## Strategic decisions

- **Keep the wire constraint; enforce at the tool layer** (vs. relaxing the
  wire to accept arbitrary `re` strings) — the fleet runs mixed extension
  versions (v0.13.0 peers + trunk); a wire-format change requires paired
  deployment, while the tool-layer fix deploys per-sender and fails fast
  everywhere. Relaxing the wire remains a possible follow-up if thread-token
  correlation in `re` is ever wanted as a first-class feature.

## Simplification opportunity

Post-fix, the workaround convention ("thread tokens in body, never non-UUID
`re`") stops being tribal knowledge the fleet has to relay — the tool error
teaches it at the point of use, and the skill-doc rule becomes a restatement
rather than the only defense. No code deletion; the deprecated `request()`
path already sends `re=null` and needs no change.

## Scope / acceptance

- [ ] `agent_send` (pi tool + MCP tool) with non-UUID `re` returns an
      immediate parameter error naming the constraint (no 5s wait, no wire
      traffic) — unit tests on both surfaces
- [ ] Envelope-UUID and absent `re` pass through unchanged (regression:
      today's delivered matrix stays green)
- [ ] Broker receiving a non-UUID `re` envelope appends an audit line and
      NACKs the sender with `invalid_envelope` (integration test; the
      silent-drop path is gone)
- [ ] Agent-network skill + both tool descriptions carry the envelope-id-only
      rule

## Provenance (diagnosis record, 2026-10-09)

Defect report from fleet-root (projects#2, msg id 01a121db-2c2d-763a-be8c-dec32bd7153f):
pair-only delivery failure between `/home/agent/projects/nextup@nextup`
(pi resident) and `/home/agent/projects/nextup/.claude/worktrees/mesh@nxuC`
(Claude lane MCP) — both directions agent_send→send-timeout while every
control (fleet-root, outpost) delivered. Fleet investigation followed with
resident-designed discriminators; successive hypotheses (stale 0.87.1 peer,
leader version mix, mid-turn busy drops, bounded-inbox byte budget, size
sensitivity) each falsified by controls.

**Root cause (audit-backed):** every failing send carried a non-envelope
`re` token; the broker audit showed ZERO such envelopes — they never routed.
`envelope.ts parse()` rejects non-UUID `re` with `EnvelopeError`; the
broker's receive path swallows it (`if (e instanceof EnvelopeError) return;`)
→ no ACK → 5s `sendWithAck` timeout surfaced as "No ACK … transport error".
Identical in v0.13.0 and trunk (fleet-wide exposure). Confirmed by corrected
control from outpost (`re="nonexistent-repro-token-002"` → identical timeout
signature). One diagnostic correction on record: outpost's two earlier
"delivered" controls were invalid (token written in body prose, `re`
parameter never set) — the resident's discriminator result was correct as
reported. All observations reconcile with zero residue: both-direction
failures (both lanes used the item-id convention), controls passing
(envelope-id or no `re`), the apparent "healing" at 18:14:58Z (repro
protocol switched to no-`re` sends). The dead-MCP-child wedge earlier in the
day was real but separate (fleet-root observation).

Full delivery matrix and hypothesis history in git history of this file
(commits ea00940ca, a62439bed, ba7c23613). Workaround already fleet-adopted:
`re` only ever null or an envelope id; thread tokens in body.
