---
id: release-v0.1.0
kind: release
stage: quality-gate
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
<populated in Phase 4>
