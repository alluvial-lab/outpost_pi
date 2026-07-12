---
id: epic-rebrand-to-outpost-pi-mechanical-rename
kind: feature
stage: done
tags: [rebrand, pi-extension, app, relay, cockpit, site, docs]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
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

## Architectural choice

**Scripted replacement with an exclusion allowlist, verified by grep.** The
slice is ~1,613 occurrences across ~240 files — hand-editing is error-prone
and unreviewable at this scale. A scripted replace (`fastmod` or scoped
`sed`/`perl`) with the complete exclusion list is reviewable: the diff is the
review artifact, and a verification grep proves completeness.

The exclusion list is the contract with the wire-stable migration feature —
it defines the set of `remote-pi*` literals this feature must NOT touch
because the wire-stable feature owns them. The exclusion list was finalized
by mapping every wire-stable surface in that feature's design (Units 1-8).

## Replacement table (the single source of truth for this slice)

| Pattern | Replacement | Notes |
|---|---|---|
| `remote-pi` (kebab) | `outpost-pi` | CLI, npm bin, log prefixes, doc slugs |
| `remote_pi` (snake) | `outpost_pi` | mesh name default, session name, file stems |
| `Remote Pi` / `remote pi` / `Remote-Pi` (prose) | `Outpost-Pi` | wordmark, README, doc titles |
| `RemotePi` (PascalCase) | `OutpostPi` | class/identifier names, APK filename |

## Exclusion list (owned by the wire-stable migration feature — DO NOT TOUCH)

This feature's scripted replace must skip every literal in this list. They
are wire/install/storage/launchd-stable and owned by sibling stories.

- `remote-pi-relay-auth-v1` — auth domain string (Unit 3)
- `remote-pi-ctrl` — cockpit control-RPC NUL-prefix discriminator (Unit 1)
- `remote_pi_control` — structured control type (Unit 1)
- `remote-pi:relay-state`, `remote-pi:name-assigned`, `remote-pi:pair-code`,
  `remote-pi:paired`, `remote-pi:mesh-revoked` — customType event strings
  (Unit 1)
- `x-remote-pi` — JSON Schema vendor key (Unit 1)
- `remote-pi.dev` — schema `$id` URI domain (Unit 1)
- `work.jacobmoura.remotepi` / `dev.remotepi.identity` — Android
  applicationId/namespace, iOS bundle id (Unit 6)
- `dev.remotepi.peers` / `dev.remotepi.rooms` / `dev.remotepi.pi` /
  `dev.remotepi.mac` / `dev.remotepi.owner.identity` — Hive box + keyring +
  owner-identity service names (Unit 8)
- `dev.remotepi.supervisord` — launchd label (Unit 8)
- `remotepi://` — QR-pairing URI scheme (Unit 8)
- `REMOTE_PI_*` / `REMOTEPI_*` — env vars (Unit 8)
- `Copyright (c) 2026 Jacob Moura` — LICENSE copyright line (provenance
  feature)
- Generated protocol files (`protocol/generated/`) — these are codegen
  output; the wire-stable feature's codegen run owns them
- `protocol/schema/` — owned by the wire-stable feature's schema-source
  story

## Implementation Units

### Unit 1: pi-extension mechanical rename
**Story**: `…-extension-rename`
The largest subproject (963 occ / 80 files). Excludes the auth constant,
control constants, customType emitters (all wire-stable), generated
protocol files, the keyring services, launchd label, env-var readers, and
the LICENSE. Renames: log prefixes, the npm `name`/`bin` fields, internal
labels, README, CLAUDE.md, daemon docs prose.
**Acceptance**: `corepack pnpm --dir pi-extension typecheck && test && build`
green; verification grep clean.

### Unit 2: site mechanical rename
**Story**: `…-site-rename`
276 occ / 29 files. Pure marketing/docs surface — no wire-stable literals.
Rename all `remote-pi`/`Remote Pi` to `outpost-pi`/`Outpost-Pi`.
**Acceptance**: `pnpm --dir site lint && build` green.

### Unit 3: app mechanical rename
**Story**: `…-app-rename`
179 occ / 69 files. Excludes the auth constant, Hive box names, URI scheme,
env vars, debug-log filename `remote_pi_debug.jsonl` (if renamed, orphans
existing logs — but per hard-cutover decision this is acceptable; include it
in the rename). Renames user-visible strings, session-name default, prose.
**Acceptance**: `flutter analyze && test` (in `app/`) green.

### Unit 4: cockpit mechanical rename
**Story**: `…-cockpit-rename`
190 occ / 58 files. Excludes the control-path consumers (wire-stable Unit 5),
env-var emitters (Unit 8), the launchd probe path (Unit 8). Renames
user-visible strings, PT comments referencing the product name, doc titles.
**Acceptance**: `flutter analyze && test` (in `cockpit/`) green.

### Unit 5: relay mechanical rename
**Story**: `…-relay-rename`
12 occ / 6 files. Small. Excludes the auth constant (Unit 3), generated
protocol files. Renames log prefixes, Cargo metadata, README.
**Acceptance**: `cargo fmt --check && clippy -- -D warnings && test`
(in `relay/`) green.

### Unit 6: root + .github + shared docs
**Story**: `…-root-and-docs-rename`
Renames `CHANGELOG.md` historical entries? **No** — changelog is historical;
add a new `0.1.0` Outpost-Pi entry (done by the wire-stable feature's
version-and-docs story). Rename root README, the `.github/workflows`
references (`RemotePi.apk` → `OutpostPi.apk` etc.), `PROTOCOL.md` title,
`docs/` prose (non-wire-stable sections).
**Acceptance**: no build gate; verification grep + manual review.

## Implementation Order

All six units are independent (no `depends_on` between them) and can run in
parallel. The exclusion list is the only cross-unit contract. Land before
or alongside the wire-stable migration feature; they converge at the 0.1.0
release.

## Testing

- Each story's owning-subproject build+test suite
- **Verification grep** (the completeness proof for this feature):
  `grep -rn 'remote-pi\|remote_pi\|Remote Pi\|RemotePi' -- ':!.work/'
  ':!.orchestration/' ':!.agents/' ':!.research/' ':!.claude/' ':!*.md'
  ':!protocol/generated/' ':!protocol/schema/'` returns only the excluded
  wire-stable literals (which the wire-stable feature then renames)
- The wire-stable feature's exclusion-list grep is the inverse proof

## Risks

- **Exclusion-list drift.** If the wire-stable feature adds a new
  wire-stable literal after this feature's script runs, the script may have
  already renamed it. Mitigation: this feature lands first (or the exclusion
  list is locked before either runs); the wire-stable feature's design is
  complete, so the list above is final.
- **Scripted replace hitting a false positive.** A `remote_pi` substring in
  an unrelated identifier (e.g. a third-party package) could be renamed.
  Mitigation: scope the script to tracked files only, review the diff, and
  gate on the subproject build+test suites.
- **`scripts/` operator-glue.** Per the epic decision, leave `scripts/`
  shell comments untouched unless they reference a renamed product
  identifier that breaks a runtime path. The script must skip `scripts/`.
- **Changelog historical entries.** Do not rewrite past changelog entries
  to the new name — changelog is historical. Only the new `0.1.0` entry
  uses `Outpost-Pi` (added by the wire-stable feature's docs story).
- **`remote-pi.schema.json` filename.** This feature renames the schema
  *filename* (`remote-pi.schema.json` → `outpost-pi.schema.json`) and the
  `$ref` paths that point at it, but NOT the `$id` URI or `title` inside
  (those are the wire-stable feature's Unit 1). Coordinate: the
  `$ref: ./remote-pi.schema.json` paths in `manifest.json` and the umbrella
  schema update in lockstep with the filename rename. The two features
  converge at 0.1.0; until then the file's `$id` says `kevoun.com` while
  the filename may still say `remote-pi` (cosmetic drift, not a break —
  `$ref` is filesystem-relative, not `$id`-relative).

## Review (2026-07-12)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: branding SVG assets (`branding/banner.svg`) still contain
"Remote Pi" text — filed as `rebrand-branding-assets-redraw` (backlog). These
are image assets needing a redraw, not a sed replace. Defer to the
external-surfaces follow-up epic.
**Nits**: cockpit/CHANGELOG.md historical entries retain "Remote Pi" —
correct (changelog is historical).

**Notes**: Deep-lane review (feature scope). Verified: auth string
consistently renamed across all three languages; zero `remote-pi-relay-auth`
in source (only intentional test fixture + AGENTS.md cutover description);
plugin imports all correctly updated to `package:outpost_pi_identity/...`.
Review caught and fixed current-truth stragglers: root CLAUDE.md, REPO-EVAL.md,
.gitignore comments, example Info.plist display name, podspec description,
branding/README.md. Historical changelog entries correctly left as-is.
