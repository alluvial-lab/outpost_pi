---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-version-and-docs
kind: story
stage: review
tags: [rebrand, docs, release]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-relay-auth
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-extension-emitters
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-cockpit-consumers
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-app-install-and-plugin
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-storage-keyring-daemon-env
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
---

# Version reset to 0.1.0 + durable-docs roll-forward

## Scope

Unit 7 of the wire-stable migration feature — the release-binding unit.
Reset all subproject versions to 0.1.0 and roll the durable docs
(AGENTS.md, PROTOCOL.md) forward to the new auth string + 0.1.0 pairing
as current truth. Depends on all prior units because it's the last thing
that lands before the release.

## Units implemented
- Unit 7 (version + docs)

## Changes
- Version reset:
  - `pi-extension/package.json` `0.6.0` → `0.1.0`
  - `app/pubspec.yaml` `1.2.0+7` → `0.1.0+0`
  - `relay/Cargo.toml` `0.2.2` → `0.1.0`
  - `cockpit/pubspec.yaml` `1.5.1+9` → `0.1.0+0`
  - `site/package.json`, `rp-s3/Cargo.toml` already `0.1.0` — hold
- Durable docs (roll forward in-place, current truth, no migration prose):
  - `AGENTS.md` "Paired wire changes" section: the
    `app-v1.2.0 ↔ relay-0.2.0` and `relay-0.2.0 ↔ extension-0.6.0` pairings
    → the new `app-0.1.0 ↔ relay-0.1.0 ↔ extension-0.1.0` pairing for the
    `outpost-pi-relay-auth-v1` rename. Update the auth domain-separation
    bullet and the `to_room` bullet's version refs.
  - `PROTOCOL.md` auth-domain section: `remote-pi-relay-auth-v1\n` →
    `outpost-pi-relay-auth-v1\n` (current truth)
  - `CHANGELOG.md`: add the `0.1.0` Outpost-Pi rebrand entry (changelog is
    the one durable doc that IS historical — entries accumulate, this one
    records the rebrand + version reset)

## Acceptance Criteria
- [x] All four subproject manifests read `0.1.0` (site/rp-s3 hold at 0.1.0)
- [x] `AGENTS.md` paired-wire table reflects `app-0.1.0 ↔ relay-0.1.0 ↔
      extension-0.1.0` and `outpost-pi-relay-auth-v1`; no stale
      `remote-pi-relay-auth-v1` or old version refs in that section. Also
      rolled forward the relay-container commands (image tag, OUTPOSTPI_* env
      vars) and the pi-extension debug-log env var (OUTPOST_PI_DEBUG_LOG).
- [x] `PROTOCOL.md` carries `outpost-pi-relay-auth-v1` as current truth
- [x] `CHANGELOG.md` has a `0.1.0` entry recording the Outpost-Pi rebrand

## Implementation notes

Rolled forward in-place per rolling-foundation (current truth, no migration
prose) except CHANGELOG (which is historical — entries accumulate). Version
reset: pi-extension 0.6.0→0.1.0, app 1.2.0+7→0.1.0+0, relay 0.2.2→0.1.0,
cockpit 1.5.1+9→0.1.0+0, site/rp-s3 hold at 0.1.0. AGENTS.md paired-wire
section rewritten for the 0.1.0 pairing + the new cockpit-control
      discriminator pairing + the storage/keyring/launchd cutover (incl. the
      manual launchctl bootout cleanup note for the old daemon label).
Relay-container commands updated to outpost-pi-relay:0.1.0 + OUTPOSTPI_*
env vars. PROTOCOL.md auth string updated. CHANGELOG 0.1.0 entry added.
