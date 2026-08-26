---
id: gate-docs-pattern-paired-brightness-contract-vars
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Paired-brightness pattern examples use retired CSS variable names

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/paired-brightness-semantic-palettes.md:30-34,67-73`
- Contradicting source: `.mockups/design-system/tokens.css:27-35,95-118`; `site/src/app/globals.css:9-26`

## Current doc text
> `--op-bg: #0d1210` and `--op-text: #e8ece9`
>
> `:root { --op-bg: #0d1210; }`

## Contradiction
The canonical theme contract no longer defines `--op-bg` or `--op-text`; it defines roles such as `--color-bg-primary`, `--color-text-primary`, and `--color-accent`. The pattern's code samples therefore cannot be copied into the current CSS contract and misidentify the site token names.

## Required edit
Replace the retired `--op-*` examples with the current canonical role names and retain the explicit light/system selectors. Keep the fixture and synchronizer references aligned with `branding/theme-contract.json` and `scripts/sync-brand-contracts.py`.
