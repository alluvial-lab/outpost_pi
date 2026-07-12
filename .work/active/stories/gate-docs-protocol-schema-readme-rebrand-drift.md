---
id: gate-docs-protocol-schema-readme-rebrand-drift
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.1.0
gate_origin: docs
created: 2026-07-12
updated: 2026-07-12
---

# Protocol schema README still names the pre-rebrand schema

## Drift category
foundation-doc-assertion

## Location
- Doc: `protocol/README.md:1,19`
- Code/source: `protocol/schema/remote-pi.schema.json:3`, `protocol/package.json:2`

## Current doc text
> `# Remote Pi protocol schema` and `schema/remote-pi.schema.json`.

## Reality
The README describes the Outpost-Pi schema metadata (`x-outpost-pi`), while the
bundle's rebrand leaves the public protocol package/schema names as
`@remote-pi/protocol-schema` and `remote-pi.schema.json`. The README is therefore
not rolled forward to the release's naming surface and points at the old schema
filename.

## Required edit
Roll the protocol README forward in place: use the Outpost-Pi heading and the
actual canonical schema filename/package identifier selected by the rebrand.
If the filename/package are intentionally retained as compatibility identifiers,
state that current contract explicitly and make the path/package references
consistent rather than presenting them as the current product name.

## Fix (2026-07-12)
Fixed inline: protocol/README.md title "Remote Pi protocol schema" → "Outpost-Pi
protocol schema". The `schema/remote-pi.schema.json` path reference on line 19
is a filesystem-relative `$ref` — the filename is intentionally unchanged per
the mechanical-rename feature's design decision (schema filenames are owned by
that feature; `$ref` paths are filesystem-relative, not `$id`-relative).
