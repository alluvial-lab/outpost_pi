---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: done
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

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected high reasoning for the security-sensitive cross-stack feature).
- Review weight: `standard` (caller default); child story review is not applicable.
- Files changed: `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`, `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`, `cockpit/test/data/pi_rpc_process_control_test.dart`.
- Tests added: metadata-only formatter regressions for prompt/tool/image/token canaries, malicious type/id fields, malformed JSON, non-object frames, fixed categories, and generated request ids.
- Simplification: removed `RpcUnknown.raw`; the adapter no longer retains untrusted malformed/non-object lines.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: `flutter test --no-pub test/data/pi_rpc_process_control_test.dart test/data/rpc_event_mapper_test.dart` passed (10 tests).
