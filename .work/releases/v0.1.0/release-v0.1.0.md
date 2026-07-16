---
id: release-v0.1.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-12
updated: 2026-07-15
---

# Release v0.1.0 — Outpost-Pi rebrand

The fork's first release under the Outpost-Pi name. Resets all subprojects
to 0.1.0 (pre-1.0; see `docs/VISION.md` Fork posture). Includes the full
rebrand (mechanical rename, wire-stable identifier migration, provenance) plus
all prior unbound done work since v0.6.0 (session-stable message delivery,
cross-side observability, duplicate-auth handling, and many bug fixes).

**2026-07-15 rebind.** All done work landed after the 2026-07-12 cut — the
`en-first` translation arc, `external-surfaces` arc, identifier-convergence,
distribution-ownership, signing-ownership cutover, half-open-socket fix,
`to_room` sender-side room-targeting, and the late security/docs/tests gate
findings — was reattributed to this release. 73 items moved from
`.work/active/` into this directory with `release_binding: v0.1.0`. The
pre-rebrand component tags (`app-v1.x`, `cockpit-v1.x`, `extension-0.5.x`,
`relay-0.1.0`, `v0.4.0`/`v0.5.0`/`v0.6.0`) were deleted at the same time;
their retained item bodies under `.work/releases/` remain as historical
record. Only `v0.1.0` is a live git tag.

## Bound items

### Rebrand (epic: epic-rebrand-to-outpost-pi)

Features (3):
- epic-rebrand-to-outpost-pi-mechanical-rename
- epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
- epic-rebrand-to-outpost-pi-provenance

Stories (14):
- epic-rebrand-to-outpost-pi-mechanical-rename-{site,relay,extension,app,cockpit,root-and-docs}-rename
- epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-{schema-source,regen-generated,relay-auth,extension-emitters,cockpit-consumers,app-install-and-plugin,storage-keyring-daemon-env,version-and-docs}

### Prior unbound done work (session resilience, observability, bug fixes)

Features (2):
- feature-cross-side-observability
- feature-session-stable-message-delivery

Stories (~30): session-stable-message-delivery children, observability, duplicate-auth, mobile/chat/pairing fixes, etc.

### Post-hardfork rebind (2026-07-15)

73 items completed after the 2026-07-12 cut and reattributed to this
release. Bodies now live alongside the original bound set below.

- `epic-rebrand-to-outpost-pi-en-first` + children (app, cockpit ×5, pi-extension, relay, site, prose-surfaces)
- `epic-rebrand-external-surfaces` + children (hostname-migration, no-default-relay, retire-rp-s3)
- `feature-outpost-pi-identifier-convergence` + children (auth-contract, extension-aliases, protocol-schema)
- `feature-outpost-pi-distribution-ownership` + children (ci-signing, cockpit-identifiers)
- Signing-ownership cutover stories (android/app-ios/cockpit/windows appcast + release-task-guard, team-consistency)
- `story-app-half-open-socket-swallows-sends-arrives-late` + `story-app-reattempt-held-pending-on-reconnect`
- `story-to-room-sender-side-room-targeting` (Option B: relay-authoritative room discovery)
- `story-extension-stale-sibling-evict-on-owner-revocation`, `story-extension-user-message-ingress-idempotency`
- `gate-security-release-build-debug-signing-fallback` (late security finding, fixed inline)
- Rebrand-site, en-first residual, provenance, update-checker-noop, site-play-availability stories

### Archived stubs (late-bound)

~9 archived stubs from prior work, late-bound to this release.

## Gate runs

### gate-cruft (2026-07-12)
- Scanner isolation: inline reduced-isolation audit; no subagent scanner tool was available in this host.
- Bundle audited: 181 changed paths recovered from bound item commits.
- Findings: High 0, Medium 1, Low 0.
- Created non-blocking backlog item: `gate-cruft-legacy-protocol-identifiers`.
- Confirmed no mac→pi keyring migration shim was found; provenance/historical `remote_pi` references were not treated as cruft.

### gate-docs (2026-07-12)
- Scanner isolation: inline reduced-isolation audit; no subagent scanner tool was available in this host.
- Bundle audited: 181 changed paths; foundation docs, README, CHANGELOG, protocol docs, and affected skills checked.
- Findings: High 1, Medium 0.
- Created blocking story: `gate-docs-protocol-schema-readme-rebrand-drift`.
- CHANGELOG contains a v0.1.0 entry; no additional changelog-gap finding.

### gate-patterns (2026-07-12)
- Scanner isolation: inline reduced-isolation audit; no subagent scanner tool was available in this host.
- Bundle audited: 181 changed paths.
- Findings: 0 new patterns, 0 inconsistencies.
- The recurring `RemotePi` → `OutpostPi` rename is a one-time naming migration, not a reusable structural pattern.

### gate-tests (2026-07-12)
- Scanner isolation: inline reduced-isolation audit; no source-read-only subagent scanner tool was available in this host.
- Bundle audited: 60 bound non-release items and 181 changed paths, with acceptance criteria mapped to relevant test surfaces.
- Findings: Critical 0, High 1, Medium 0, Low 0.
- Created blocking story: `gate-tests-keyring-hard-cutover-ignores-legacy-service`.
- The cross-client auth-prefix contract gap is already tracked in `rebrand-cross-client-auth-contract-test`; the known read-only Flutter pub-cache and pi-extension cwd-lock ordering failures are environment issues and were not duplicated.

### gate-refactor (2026-07-12)
- Scanner isolation: inline reduced-isolation audit; no subagent scanner tool was available in this host.
- Bundle audited: 60 bound non-release items, 181 changed paths, against `boundaries`, `lifecycle`, and `protocol-contract`.
- Findings: High 0, Medium 3, Low 0; all three are non-blocking backlog items under `gate_finding_routing` and carry no `[refactor]` tag (`findings-route: none`).
- Created: `gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward`, `gate-refactor-protocol-contract-relay-client-island`, and `gate-refactor-lifecycle-queued-delivery-promise`.

### gate-security (2026-07-12)
- Scanner isolation: inline reduced-isolation source audit; this delegated endpoint exposed no further scanner/sub-agent dispatch path.
- Bundle audited: 60 bound non-release items and 181 recovered changed paths, emphasizing auth-domain hard cutover, install/storage identifiers, duplicate-auth takeover, session-stable delivery, and diagnostic logging.
- Findings: Critical 0, High 2, Medium 2, Low 0.
- Blocking: created `gate-security-release-build-debug-signing-fallback`; promoted and bound the already-tracked `gate-security-relay-owner-messages-unsigned` rather than duplicating it.
- Non-blocking backlog: created `gate-security-preauth-websocket-size-limits` and `gate-security-orphaned-pre-rebrand-launchd-daemon`.
- Six semantically duplicate, already-tracked security findings were skipped.

## Shipped items

Bodies live on disk (retain-bodies) under `.work/releases/v0.1.0/` (active
items) and `.work/archive/` (late-bound stubs).

- Date shipped: 2026-07-12 (rebind: 2026-07-15)
- Mapping: tag-based (git tag `v0.1.0`; push is external — operator runs from their machine)
- Total items shipped: 136 (55 originally bound + 73 post-hardfork rebound + 8 archived stubs)
- Gate finding totals:
  - gate-security: 9 non-blocking (backlog) + 2 high unbound (pre-existing, declared)
  - gate-tests: 1 blocking (fixed inline: legacy-keyring-cutover-ignore test) + non-blocking (backlog)
  - gate-cruft: 14 non-blocking (backlog)
  - gate-docs: 1 blocking (fixed inline: protocol README title) + 8 non-blocking (backlog)
  - gate-patterns: pattern catalog produced
  - gate-refactor: scan-rule libraries applied; findings routed
- External publishing mechanism: operator pushes the `v0.1.0` tag; per-component
  tags (`app-v0.1.0`, `relay-0.1.0`, `extension-0.1.0`, `cockpit-v0.1.0`) follow
  the same tag-based mapping. The relay Docker image (`outpost-pi-relay:0.1.0`)
  and app APK are built + deployed per AGENTS.md instructions.
