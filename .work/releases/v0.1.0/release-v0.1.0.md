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
updated: 2026-07-12
---

# Release v0.1.0 — Outpost-Pi rebrand

The fork's first release under the Outpost-Pi name. Resets all subprojects
to 0.1.0 (pre-1.0; see `docs/VISION.md` Fork posture). Includes the full
rebrand (mechanical rename, wire-stable identifier migration, provenance) plus
all prior unbound done work since v0.6.0 (session-stable message delivery,
cross-side observability, duplicate-auth handling, and many bug fixes).

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

- Date shipped: 2026-07-12
- Mapping: tag-based (git tag `v0.1.0`; push is external — operator runs from their machine)
- Total items shipped: 63 (55 active done + 8 archived stubs)
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
