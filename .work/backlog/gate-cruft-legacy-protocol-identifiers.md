---
id: gate-cruft-legacy-protocol-identifiers
created: 2026-07-12
updated: 2026-07-12
tags: [cleanup, docs]
---

# Remove or explicitly document leftover pre-rebrand protocol identifiers

## Confidence
Medium

## Category
compatibility shim / stale identifier

## Location
- `protocol/package.json:2` — `@remote-pi/protocol-schema`
- `protocol/schema/remote-pi.schema.json:3` — legacy filename and `$id`
- `protocol/README.md:19` — legacy schema path

## Evidence
The v0.1.0 rebrand changes the protocol vendor metadata to `x-outpost-pi`,
while these source/package identifiers remain `remote-pi`. The rebrand notes
say the mac→pi keyring migration was removed and the product identifiers were
hard-cut over; no migration/compatibility behavior was found for these protocol
package/path names.

## Removal
Remove the unused legacy package/path identifiers and rename references to the
Outpost-Pi identifiers, or add a narrowly scoped explanation if a stable
published package/path is intentionally retained. Do not add a compatibility
shim solely to preserve an internal pre-rebrand name.
