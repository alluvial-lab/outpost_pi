---
id: gate-security-relay-rusqlite-libsqlite3-upgrade
created: 2026-11-20
updated: 2026-11-20
tags: [relay]
---

# Upgrade `rusqlite` (`0.40` → `0.41+`) to pick up `libsqlite3-sys >= 0.39.0` (`RUSTSEC-2026-0459`)

Parked from `v0.14.0` release-gate `security` dependency pass (medium, CVSS 6.8, non-blocking).

## Context

`cargo update` in `relay/` cleared 12 of 13 `Cargo.lock` advisories (including all high advisories and both unsound warnings), leaving only `libsqlite3-sys@0.38.2` (`RUSTSEC-2026-0459`, C SQLite CVE-2026-119375, medium 6.8, patched in `>= 0.39.0`). Because `relay/Cargo.toml` pins `rusqlite = { version = "0.40", features = ["bundled"] }`, moving `libsqlite3-sys` to `>= 0.39.0` requires a breaking Cargo major upgrade of `rusqlite` (`0.40` → `0.41+` / `0.43`).
