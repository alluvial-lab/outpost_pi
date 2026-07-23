---
id: gate-cruft-unused-parse-hello-wrapper
kind: story
stage: drafting
tags: [cleanup, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-19
---

# Remove the test-only parse_hello passthrough wrapper

## Severity
Low

## Confidence
Medium

## Category
passthrough wrapper

## Relevance
Release-relevant

## Decision required
no

## Location
`relay/src/auth/challenge.rs:67-69`

## Evidence
```rust
pub fn parse_hello(line: &str) -> Result<VerifyingKey, AuthError> {
    Ok(parse_hello_bootstrap(line, 0)?.verifying_key)
}
```

Repository search found one caller, `relay/src/auth/auth_test.rs:45`; production authentication calls `parse_hello_bootstrap` directly.

## Removal
Update the remaining test to call `parse_hello_bootstrap`, assert the same error, remove `parse_hello`, and remove the now-unneeded `VerifyingKey` return-surface documentation. No external relay consumer was found in this repository, so this remains medium-confidence rather than tool-proven dead code.

## Gate scan context
Scanner execution was inline at the operator's direction, with reduced isolation and no scanner sub-agent.
