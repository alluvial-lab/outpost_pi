---
id: story-cockpit-signing-runbook-ownership-cutover
kind: story
stage: implementing
tags: [cockpit, docs, release, rebrand]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-14
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
