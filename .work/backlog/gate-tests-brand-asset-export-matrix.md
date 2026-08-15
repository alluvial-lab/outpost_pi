---
id: gate-tests-brand-asset-export-matrix
created: 2026-08-15
updated: 2026-08-15
tags: [branding, workflow, testing]
---

# Brand asset generator's platform export matrix is unverified

Post-hoc v0.5.0 tests-gate finding. Severity: Medium.

## Location
`scripts/generate-brand-assets.py:81-96` (explicit Android density table) vs
`:99,108` (iOS/macOS iterate existing files with globs — a missing catalog
entry is silently skipped); ICO matrix at `:120`.

## Work
Manifest-based asset check asserting the exact expected paths + dimensions,
RGB/no-alpha for iOS/macOS, Android transparency, ICO embedded sizes, favicon
dimensions, and byte-equality of copied SVGs with the canonical
`branding/` source; require a clean regeneration diff. Pairs with the
`canonical-mark-rasterization-fanout` pattern's drift risks.
