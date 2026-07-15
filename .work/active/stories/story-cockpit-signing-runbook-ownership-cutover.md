---
id: story-cockpit-signing-runbook-ownership-cutover
kind: story
stage: done
tags: [cockpit, docs, release, rebrand]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Finish the Cockpit signing and bundle-ID cutover runbook

## Review finding

**Severity:** Blocker

The feature required inherited credential paths and signing metadata to leave
the active packaging runbook, and its known one-way bundle-ID cutover to be
documented durably. `cockpit/packaging/README.md:14` still names the inherited
Apple team `U843T2P7A2`, while line 85 still instructs local notarization through
an inherited `/Users/jacob/.../AuthKey_*.p8` path. The same runbook has no note
that changing to `dev.kevoun.outpostpi.cockpit` prevents in-place upgrade from
existing `work.jacobmoura.cockpit` installations; line 133 only discusses a
manual install caused by disabled appcast publication, which is a different
constraint.

This leaves a direct design-requirement miss and makes the intentional breaking
identity cutover a surprise outside the transient feature body.

## Required outcome

- Remove the inherited Apple team and absolute credential path from the active
  runbook; parameterize local notarization inputs without committing operator
  values or secrets.
- Make the credential inventory match the workflow's current required secrets
  and the fact that the operator Developer ID is not yet provisioned.
- Document the old-to-new macOS bundle-ID reinstall requirement and distinguish
  it from the separate disabled-self-update/manual-install state.
- Re-run the inherited-identity grep while preserving the historical
  `cockpit/CHANGELOG.md` record and genuine `jacobaraujo7/*` dependencies.

## Implementation notes
- Files changed: `cockpit/packaging/README.md`
- Removed the inherited Apple team ID `U843T2P7A2` from the identity table; replaced with "operator-owned, supplied via `APPLE_TEAM_ID` secret (not yet provisioned)."
- Removed the inherited `/Users/jacob/.../AuthKey_3Y2J8MA3M4.p8` notarization key path; the notarize step now reads `APPLE_API_KEY_FILE` / `APPLE_API_KEY_ID` / `APPLE_API_ISSUER` from env with `:?` fail-closed.
- Updated the CI secrets inventory to list all 7 Apple secrets (incl. `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`) and to state the operator Developer ID is not yet provisioned (workflow fails closed until secrets exist).
- Added a **one-way bundle-ID cutover** callout documenting that moving from `work.jacobmoura.cockpit` to `dev.kevoun.outpostpi.cockpit` prevents in-place upgrade, distinguished from the separate disabled-self-update/manual-install state.
- Verification: `rg 'U843T2P7A2|/Users/jacob|jacobmoura|Developer ID Application: Jacob Moura' cockpit/ .github/workflows/cockpit-release.yml` returns only the intentional one-way-door warning naming the old ID being migrated from, and a harmless doc-comment example in `session_history_impl.dart`.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Review (2026-07-15, second pass)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Deep-feature second-pass verification confirmed the inherited team ID and credential path are gone from the Cockpit runbook, local notarization inputs fail closed through environment variables, the seven CI secrets are documented, and the one-way bundle-ID reinstall cutover is distinct from dormant self-update. Story advanced `review -> done`.
