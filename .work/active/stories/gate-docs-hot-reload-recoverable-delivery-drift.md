---
id: gate-docs-hot-reload-recoverable-delivery-drift
kind: story
stage: done
tags: [pi-extension, docs]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: docs
created: 2026-08-11
updated: 2026-08-11
---

# Hot-reload docs/comments claim a recoverable-delivery contract the code does not implement

## Severity
High (docs drift — actively misleading; cross-gate: docs D1+D2, cruft C3).

## Location
AGENTS.md:263-265 and :308; pi-extension/src/index.ts:2546-2555 (quiescing comment).

## Evidence
Docs/comments claim restart fires "after the response fully streams to the app" and describe a recoverable delivery_error / delivery_pending response. Reality: agent_settled is NOT an end-to-end delivery ack (AGENTS.md:274-280 itself says reconnect hydration is required); _sendDeliveryError emits code "internal_error" (index.ts:2278-2285); the app only gives special replay handling to delivery_pending (sync_service.dart:1267-1270), so the emitted internal_error is treated as a failed send. The quiescing comment names delivery_pending while the code calls _sendDeliveryError.

## Remediation direction
Align AGENTS.md and the code comments with reality: restart fires at settlement, and final-frame receipt is not acknowledged; the recoverable/resend contract is aspirational future work (tracked in backlog-recoverable-delivery-resend-contract). Fix the quiescing comment to say delivery_error (not delivery_pending) and the resend-on-reconnect caveat. No code-contract change in this item.

## Implementation notes
- Execution capability: inline host execution; the bounded docs/comment-only correction had no coordination need.
- Review weight: standard (project default), using the required bounded inline standalone-story review with no independent reviewer.
- Files changed: `AGENTS.md` and `pi-extension/src/index.ts` now describe settlement rather than delivery acknowledgement, distinguish failed-send behavior from `delivery_pending`, and identify automatic resend as aspirational.
- Tests added/removed: none; this item intentionally changes no code contract.
- Verification: re-read the edited text against `_sendDeliveryError` (`internal_error`), `_sendDeliveryPending`, and the hot-reload settlement path; `git diff --check` passed.
- Simplification: removed contradictory recoverable-delivery claims rather than adding another explanatory layer.
- Discrepancies from design: none.
- Adjacent issues parked: none; the existing `backlog-recoverable-delivery-resend-contract` remains the future contract owner.

## Bounded inline review
Approved. The durable guidance and local comments now state the implemented behavior without implying an end-to-end acknowledgement or automatic resend, and no runtime behavior changed.
