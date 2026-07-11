---
id: epic-rebrand-to-outpost-pi-mechanical-rename
kind: feature
stage: drafting
tags: [rebrand, pi-extension, app, relay, cockpit, site, docs]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# Mechanical rename: code-internal `remote_pi`/`remote-pi` strings → `outpost-pi`

## Brief

The bulk of the rebrand: every code-internal `remote_pi` / `remote-pi` /
`Remote Pi` string that is **not** a wire/install-stable identifier becomes
`outpost-pi` / `Outpost-Pi`. This covers log prefixes (e.g. `[remote-pi]`),
the npm `name` field (`remote-pi` → `outpost-pi`) and `bin` map key, CLI
labels, internal labels, doc titles, README copy, the `site/` marketing
surface, and the `~/.pi/agent/settings.json` local-path extension
registration key.

Scope is ~1,613 occurrences across ~240 files, distributed: pi-extension
(963/80), site (269/27), cockpit (190/58), app (179/69), relay (12/6).

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi`
- Position in epic: **safe, non-breaking, parallelizable foundation slice.**
  This is the largest slice by file count but the lowest-risk — no wire,
  install, or compatibility boundary moves. It depends on nothing and
  unblocks nothing else (the wire-stable migration is an independent
  feature, not a consumer of this one's types).

## What this feature does NOT cover (owned by sibling features)
- The **wire-stable identifiers** — `remote-pi-relay-auth-v1\n`,
  `\x00remote-pi-ctrl:`, the Android `applicationId`, iOS bundle id, and the
  `remote_pi_identity` plugin namespace — are owned by
  `epic-rebrand-to-outpost-pi-wire-and-install-stable-migration`. This feature
  must NOT rename those literals; doing so out of sequence would create a
  half-migrated wire surface. The mechanical-rename replacement rules
  explicitly exclude these strings.
- The **version reset to 0.1.0** in every manifest is owned by the
  wire-and-install-stable-migration feature (it is the breaking-change
  marker that pairs the release).
- **Provenance** (LICENSE / NOTICE / README authorship credit) is owned by
  `epic-rebrand-to-outpost-pi-provenance`. The ~68 files referencing
  `jacobaraujo7`/`jacobmoura` as identifiers (URLs, homepage) are in this
  feature's scope to rebrand; only the LICENSE copyright line and NOTICE
  content are owned by the provenance feature.

## Foundation references
- `docs/VISION.md` — "Fork posture & provenance" (product name = Outpost-Pi)
- `docs/SPEC.md` — Stack table (`outpost-pi` CLI name)
- `docs/ARCHITECTURE.md` — title
- `PROTOCOL.md` — title and prose (wire-stable auth string is excluded here)
- Parent epic `## Strategic decisions` — casing: `Outpost-Pi` wordmark,
  `outpost-pi` lowercase for identifiers/CLI/npm.

## Design notes (for `/agile-workflow:feature-design`)

- **Replacement table** (the single source of truth for this slice):
  - `remote-pi` (kebab) → `outpost-pi`
  - `remote_pi` (snake) → `outpost_pi`
  - `Remote Pi` / `remote pi` / `Remote-Pi` (prose, wordmark) → `Outpost-Pi`
  - `RemotePi` (PascalCase identifiers) → `OutpostPi`
  - `remotepi` (lowercase no-sep, as in `work.jacobmoura.remotepi`) —
    **excluded**: handled by the install-stable migration feature.
- **Exclusion list** (must NOT be touched by this feature):
  - `remote-pi-relay-auth-v1` (auth domain string)
  - `remote-pi-ctrl` (cockpit control-RPC discriminator)
  - `jacobmoura.remotepi` / `remotepi.identity` (applicationId / bundle /
    plugin namespace)
  - the `Copyright (c) 2026 Jacob Moura` LICENSE line
- The design pass should consider a scripted, reviewable replacement
  (scoped sed/`fastmod` with the exclusion list) over hand-editing 240 files,
  with a verification grep confirming zero remaining `remote[ _-]?pi` outside
  the exclusion list and the generated `protocol/` fixtures.
- Leave `scripts/` operator-glue shell comments untouched unless they
  reference a renamed product identifier that breaks a runtime path.
