---
id: gate-docs-spec-offline-delivery-contract
kind: story
stage: review
tags: [pi-extension, documentation]
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Correct the offline-delivery constraint for the extension buffer

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/SPEC.md:42-45`
- Contradicting source: `pi-extension/src/extension/owner_multiplexer.ts:490-510`

## Current doc text
> **No message-queue offline delivery.** If a peer is offline, the sender gets
> `transport_error: offline` immediately. Queued-message state is a short
> in-memory Pi-side buffer for prompts held during an active turn, lost on
> restart.

## Contradiction
The extension now buffers `ServerMessage` frames for an attached app peer once
that peer is marked offline, retains bounded completed/current turn intervals,
and flushes them when the peer returns online. The absolute no-offline-delivery
claim is therefore false. Cross-PC relay forwarding still returns
`transport_error: offline`; the documented distinction must remain explicit.

## Required edit
Replace the constraint in place with the current bounded behavior: known-offline
app peers receive a per-peer, in-memory outbound turn buffer that is lost on
extension restart, while unobserved disconnects and cross-PC relay targets still
have no durable queue and report offline normally. Do not describe this as a
protocol or durable message-queue guarantee.

## Gate execution
Documentation drift audit ran inline at the operator's instruction; scanner
isolation was reduced. The finding was verified against the cited current
implementation.

## Implementation notes

- Execution capability: inline documentation repair; this is a two-file,
  evidence-backed correction with no runtime or wire change.
- `docs/SPEC.md` previously claimed universal immediate offline failure and
  described a prompt buffer. It now documents the actual bounded, per-peer
  in-memory replay of outbound server messages for relay-confirmed offline app
  peers, including active/latest-completed turn scope, best-effort flush, and
  restart loss.
- The replacement keeps the exclusion explicit: it is neither durable nor a
  protocol delivery guarantee; unobserved app disconnects and cross-PC relay
  targets retain normal offline behavior (`transport_error: offline` for
  cross-PC forwarding).
- Verification: inspected `OwnerMultiplexer` buffer, cap, turn-boundary, and
  flush paths; `corepack pnpm exec vitest run
  src/extension/owner_multiplexer.test.ts` passed (17 tests). No test was added
  because this is a documentation-only correction with existing implementation
  coverage.
