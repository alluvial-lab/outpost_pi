---
id: story-cockpit-signing-team-consistency
kind: story
stage: implementing
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
