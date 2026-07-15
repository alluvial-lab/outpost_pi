---
id: story-cockpit-windows-appcast-changelog-consistency
kind: story
stage: implementing
tags: [cockpit, docs, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Align the Cockpit changelog with disabled Windows appcast generation

## Review finding

**Severity:** Important

The repaired workflow deliberately stopped producing or signing
`appcast-windows.xml` until a WinSparkle version contract is proven, and the
packaging runbook documents that dormant state. The current Unreleased entry in
`cockpit/CHANGELOG.md:10-14` still says Cockpit self-updates on Windows and CI
publishes both `appcast-macos.xml` and `appcast-windows.xml`.

That is now false release documentation and can lead an operator or user to
expect a Windows update artifact which the workflow correctly refuses to emit.
The historical 1.0.0 release-identity record remains a keep-list item and must
not be rewritten.

## Required outcome

- Update only the current Unreleased self-update entry to state that macOS
  appcast generation exists while Windows appcast generation is intentionally
  disabled pending the documented WinSparkle smoke/contract.
- Preserve the historical `work.jacobmoura.cockpit` release record unchanged.
- Verify the workflow, packaging runbook, and Unreleased changelog agree on the
  generated appcast set; run `git diff --check`.
