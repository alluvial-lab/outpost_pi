---
id: story-cockpit-windows-appcast-changelog-consistency
kind: story
stage: done
tags: [cockpit, docs, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: v0.1.0
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

## Implementation notes
- File changed: `cockpit/CHANGELOG.md` (Unreleased `### Added` self-update entry only).
- Rewrote the entry to state Cockpit self-updates on **macOS** through Sparkle (publishes `appcast-macos.xml`), Linux retains manual download, and **Windows auto-update is not yet active** — the locked `auto_updater_windows` plugin does not expose the WinSparkle build-version API needed for a proven version contract, so the Windows appcast is intentionally not published and Windows users update by manual reinstall.
- This now agrees with the repaired workflow (Windows appcast step always-skipped) and the packaging runbook's disabled-self-update section.
- The historical `## [1.0.0]` release-identity record (`work.jacobmoura.cockpit`) is preserved unchanged.
- Verification: `git diff --check` clean.
- Discrepancies: none.
- Adjacent issues parked: none.

## Verification closure (2026-07-15, third pass)

The Unreleased entry no longer names or claims publication of `appcast-windows.xml`; it states Windows auto-update is inactive and manual reinstall is required. The historical `## [1.0.0]` record is byte-identical to its pre-fix form. The child checkpoint advanced directly to `done`. A separate unbound follow-up records the remaining macOS-runtime wording mismatch.
