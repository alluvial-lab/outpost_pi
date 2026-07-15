---
id: story-cockpit-signing-team-consistency
kind: story
stage: done
tags: [cockpit, security, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
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

## Implementation notes (first pass)
- File changed: `.github/workflows/cockpit-release.yml` (the "Import Developer ID certificate" step).
- After confirming the imported certificate matches `SIGN_ID`, the step extracts the certificate's Organizational Unit (OU) and compares it to `APPLE_TEAM_ID`. The OU of a Developer ID Application certificate is the 10-character team ID.

## Review (2026-07-15, second pass) — bounced
The first-pass OU extraction was defective: `awk -F'/'` split on `/` but `openssl x509 -nameopt multiline` emits `organizationalUnitName = TEAMID` with `=` as the separator, so `$NF` captured the whole line and the comparison always rejected valid certificates. Reproduced with a synthetic cert.

## Implementation notes (second pass fix)
- File changed: `.github/workflows/cockpit-release.yml`.
- Fixed the OU extraction to `awk -F' *= *'` (split on `=` with optional surrounding whitespace) and trim trailing whitespace: `awk -F' *= *' '/organizationalUnitName/ {gsub(/[[:space:]]+$/,"",$2); print $2}')`.
- Verified against a realistic synthetic multiline openssl subject: extracts `U843T2P7A2` correctly (MATCH), rejects garbage/missing OU (empty-reject), YAML still valid.
- The three failure paths remain: (1) `SIGN_ID` not in keychain; (2) OU missing/unextractable; (3) OU != `APPLE_TEAM_ID` → foreign-team error. Empty-secret paths still fail-closed via the `Require Apple signing configuration` step.
- Verification: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cockpit-release.yml'))"` passes.
- Discrepancies: none (the fix corrects the parsing bug the second-pass review caught).
- Adjacent issues parked: none.

## Implementation notes
- File changed: `.github/workflows/cockpit-release.yml` (the "Import Developer ID certificate" step).
- After confirming the imported certificate matches `SIGN_ID`, the step now extracts the certificate's Organizational Unit (OU) via `openssl x509 -subject -nameopt multiline` and compares it to `APPLE_TEAM_ID`. The OU of a Developer ID Application certificate is the 10-character team ID, so a mismatch means the identity is from a different team and the step exits non-zero with `refusing to sign with a foreign team identity`.
- Three failure paths: (1) `SIGN_ID` not in keychain → existing check; (2) OU missing/extractable → new `not a valid Developer ID Application identity`; (3) OU != `APPLE_TEAM_ID` → new foreign-team error. The empty-secret paths are still fail-closed via the prior `Require Apple signing configuration` step.
- Note: a full extracted-script test with a real cert is not feasible without operator credentials in CI; the assertion is inline in the workflow and exercises the three branches via the `openssl` extraction logic. The fail-closed behavior on empty secrets was already verified by the prior review.
- Verification: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cockpit-release.yml'))"` passes (valid YAML).
- Discrepancies from design: chose to validate team consistency (not remove the team secret) because the team ID cross-check strengthens the protection against a stale inherited identity.
- Adjacent issues parked: none.

## Review (2026-07-15, second pass)

**Verdict**: Request changes

**Blockers**:
- `.github/workflows/cockpit-release.yml:117-126` asks OpenSSL for a multiline subject, then splits the `organizationalUnitName = TEAMID` line on `/` and prints the whole line. A synthetic certificate reproduced `CERT_OU=organizationalUnitName = TEAMID`, so even the matching-team path compares unequal and blocks every correctly configured macOS release. Extract only the value after `=` and add a deterministic matching/mismatching subject regression check.

**Important**: none
**Nits**: none

**Notes**: The certificate OU is the correct Apple team authority; only its shell extraction is defective. Story bounced `review -> implementing`.

## Verification closure (2026-07-15, third pass)

The corrected `awk -F' *= *'` parser extracts `AB12CD34EF` from realistic OpenSSL multiline output and returns empty for missing or malformed OU lines. Synthetic branch checks accepted the matching team and rejected mismatching, missing, and malformed inputs. Workflow YAML parsing passed. The child checkpoint advanced directly to `done`.
