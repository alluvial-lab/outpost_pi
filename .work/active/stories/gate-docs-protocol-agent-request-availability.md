---
id: gate-docs-protocol-agent-request-availability
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Protocol says the still-supported agent_request tool does not exist

## Drift category
foundation-doc-assertion

## Location
- Doc: `PROTOCOL.md:137`
- Contradicting source: `pi-extension/src/session/tools.ts:212-222`

## Current doc text
> There is no `agent_wait` or `agent_request` — it is a pure event-driven pattern.

## Contradiction
The extension registers `agent_request`; it is deprecated but remains functional as a synchronous request/reply tool. The protocol currently denies an available public tool.

## Required edit
State that `agent_request` remains supported but deprecated, and that `agent_send` plus inbox observation is the preferred event-driven pattern. Do not imply the deprecated tool has already been removed.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline documentation repair; the registered tool definition is the direct availability source.
- **Change:** Corrected `PROTOCOL.md` to say `agent_request` remains supported but deprecated and blocking, with `agent_send` plus inbox observation preferred; only `agent_wait` is absent.
- **Verification:** Matched the wording to `pi-extension/src/session/tools.ts` and confirmed the denial of `agent_request` is gone. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — availability and migration guidance now agree with the public tool surface.
