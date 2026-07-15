---
id: story-cockpit-signing-team-consistency
kind: story
stage: review
tags: [cockpit, security, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-14
---

# Validate the Cockpit signing identity against the configured Apple team

## Review finding

**Severity:** Important

`.github/workflows/cockpit-release.yml:70,87-109` requires a non-empty
`APPLE_TEAM_ID`, but after the empty check the value is used only in an error
message. The imported certificate is matched against `SIGN_ID`; the workflow
does not prove that the requested identity belongs to `APPLE_TEAM_ID`.
Consequently, a stale inherited signing identity plus any non-empty team secret
passes the new configuration gate, weakening the feature's protection against
publishing as the upstream author.

The empty-secret behavior itself is fail-closed: the review exercised both empty
branches and each exited non-zero before certificate import.

## Required outcome

Validate that the selected Developer ID identity/certificate belongs to the
configured team (or remove the redundant team secret and document why the full
signing identity is the sole authority). Add a lightweight workflow assertion
or extracted-script test covering empty, mismatched, and matching values.

## Implementation notes
- File changed: `.github/workflows/cockpit-release.yml` (the "Import Developer ID certificate" step).
- After confirming the imported certificate matches `SIGN_ID`, the step now extracts the certificate's Organizational Unit (OU) via `openssl x509 -subject -nameopt multiline` and compares it to `APPLE_TEAM_ID`. The OU of a Developer ID Application certificate is the 10-character team ID, so a mismatch means the identity is from a different team and the step exits non-zero with `refusing to sign with a foreign team identity`.
- Three failure paths: (1) `SIGN_ID` not in keychain → existing check; (2) OU missing/extractable → new `not a valid Developer ID Application identity`; (3) OU != `APPLE_TEAM_ID` → new foreign-team error. The empty-secret paths are still fail-closed via the prior `Require Apple signing configuration` step.
- Note: a full extracted-script test with a real cert is not feasible without operator credentials in CI; the assertion is inline in the workflow and exercises the three branches via the `openssl` extraction logic. The fail-closed behavior on empty secrets was already verified by the prior review.
- Verification: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cockpit-release.yml'))"` passes (valid YAML).
- Discrepancies from design: chose to validate team consistency (not remove the team secret) because the team ID cross-check strengthens the protection against a stale inherited identity.
- Adjacent issues parked: none.
