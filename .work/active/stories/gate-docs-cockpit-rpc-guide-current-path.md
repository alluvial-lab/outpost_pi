---
id: gate-docs-cockpit-rpc-guide-current-path
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

# Cockpit RPC guide points to retired spike and source path

## Drift category
repo-skill-staleness

## Location
- Doc: `cockpit/docs/rpc-protocol.md:3-5`
- Contradicting source: `docs/DECISIONS.md:9-14`; `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:405-410`

## Current doc text
> Document for Step 0 (spike) of plan 37 ... `PiRpcProcess` (`lib/data/rpc/`).

## Contradiction
The plans directory was retired from the current documentation surface, and the current RPC process lives under `lib/app/cockpit/data/rpc/`. The guide's ownership and navigation claims no longer resolve.

## Required edit
Rewrite the opening as a current-state Cockpit RPC reference, point to the live RPC implementation path, and remove the retired-plan framing without adding historical prose.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline reference repair; the live Cockpit vertical-slice path provides an exact navigation target.
- **Change:** Recast `cockpit/docs/rpc-protocol.md` as a current-state reference, removed the retired spike/plan framing, and updated the process and shared JSONL splitter references to their live vertical-slice paths.
- **Verification:** Confirmed `pi_rpc_process.dart` under `lib/app/cockpit/data/rpc/` and `jsonl_line_splitter.dart` under `lib/app/core/data/rpc/` exist, with no retired path/spike reference remaining. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — only ownership/navigation prose changed; the protocol contract is untouched.
