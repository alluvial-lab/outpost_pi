---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: implementing
id: gate-security-raw-rpc-traffic-logged
tags: []
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Raw RPC traffic is printed to debug logs

## Location
cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:222

## Issue
The RPC adapter logs raw stdout lines, and the matching stdin log at line 256 can include prompts, tool results, image base64, relay/pairing tokens, and other transcript secrets.

## Recommendation
Remove raw payload logging or guard behind a debug-only redacted logger that strips prompt text, images, tokens, and tool output.

## Design checkpoint

Replace Cockpit's raw stdin/stdout `debugPrint` calls with metadata-only frame
summaries (fixed direction, UTF-8 byte count, fixed frame category, and only a
Cockpit-generated `req-<digits>` id). Delete the unused `RpcUnknown.raw` field
so malformed content is not retained after parsing.

Acceptance evidence:
- Canary prompts, tool output, image base64, tokens, and arbitrary wire
  `type`/`id` strings never appear in the summary.
- RPC decoding, correlation, control serialization, and process writes receive
  their original payload unchanged.
- Malformed/non-object stdout remains safely ignored without retaining raw text.
