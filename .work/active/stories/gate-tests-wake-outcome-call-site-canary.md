---
id: gate-tests-wake-outcome-call-site-canary
kind: story
stage: implementing
tags: [testing, refactor]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Replace the tautological wake-outcome redaction canary with a real call-site regression

## Priority

Critical

## Value evidence

Item: `feature-redact-secrets-from-diagnostic-surfaces`

Contract / risk / regression / maintenance cost: the feature records the accepted confidentiality regression in which `wake_outcome.detail` persisted raw provider error text and requires the fixed-category projection at `.work/active/features/feature-redact-secrets-from-diagnostic-surfaces.md:273`. Production performs that projection at `pi-extension/src/index.ts:2313-2323`.

The claimed canary at `pi-extension/src/session/delivery_debug_log.test.ts:108-131` never executes that production call site. It creates the three expected literal categories itself at line 118, writes those literals directly to the log adapter at lines 119-120, and then asserts the same literals and absence of secrets at lines 127-131. Reverting `index.ts` to log raw `wake.detail` would not change this test, despite the comment at lines 124-126 claiming it would fail. This is test-integrity failure: the test makes its security claim pass without observing the behavior it claims to protect.

## Gap type

test-integrity / bug-regression — tautological test masking the absence of a real regression assertion at the production diagnostic projection.

## Suggested test

```ts
test("wake failure details are categorized before delivery-log persistence", async () => {
  // Drive the existing app-message delivery seam with a wakeAgent failure whose
  // raw detail contains a unique prompt/token canary.
  // Capture the real DeliveryDebugEvent emitted by index.ts.
  expect(wakeOutcome.detail).toBe("send_failed");
  expect(JSON.stringify(wakeOutcome)).not.toContain(secretCanary);
});
```

Replace or delete the literal-only `delivery_debug_log.test.ts:108-131` case after the real call-site regression protects the contract. Do not weaken the adapter's separate faithful-persistence tests.

## Test location (suggested)

`pi-extension/src/extension.test.ts`, alongside the existing real `wake_outcome` capture at lines 4615-4651; rework/remove `pi-extension/src/session/delivery_debug_log.test.ts:108-131`.

## Gate run context

The operator required the test scanner to run inline with no nested sub-agent. This finding therefore has reduced fresh-context isolation. It was verified directly against the release-bound feature contract, production call site, and current test body.
