---
id: gate-cruft-appearance-font-hints
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, branding, cleanup]
---

# Cockpit appearance settings advertise retired font defaults (user-visible)

Post-hoc v0.5.0 cruft-gate finding. Confidence: High. Release-relevant —
shipped UI copy, not just comments.

## Location
`cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart:51`
(`hint: 'Space Grotesk · Hanken'`) and `:69` (`hint: 'JetBrains Mono'`),
while `cockpit/lib/app/core/ui/themes/app_typography.dart:39` documents
Space Mono as the default font.

## Work
Update visible hints + default descriptions to the Space Mono contract.
Small enough to fold into any cockpit touchpoint before the next release.
