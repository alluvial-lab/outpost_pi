---
id: story-identity-boot-restore-race
created: 2026-07-27
updated: 2026-07-27
tags: [app, security, bug]
---

# Fresh-install identity boot generates before the Block Store restore lands

Surfaced 2026-07-26 (phone wipe incident): after a reinstall, the first boot
ran before Google Block Store delivered the backed-up Owner identity.
`load()` legitimately returned null → the bridge treated it as first run and
generated a NEW identity. When the restore later arrived, the watch saw a
different Owner key and the transition machinery (working exactly as
designed) wiped pairings + transcripts to adopt the restored key. Operator
lost a day of app state to an avoidable cause.

The v0.3.0 hardening covers "restore races the save" (conditional re-read
before save) but not "restore is merely late" — nothing distinguishes
"no identity exists" from "identity exists but hasn't synced yet."

## Direction
Distinguish restore-pending from genuine first run at identity boot: e.g.
the platform store signals restore completion (or a bounded await of the
first sync event on a fresh install before generating), so a delayed restore
never triggers a generation-then-transition cycle. Investigate
`outpost_pi_identity` plugin semantics for Block Store/Keychain restore
timing first. Related: `feature-owner-identity-transition`,
`gate-security-identity-store-fatal-read-rotates-owner-key` (shipped),
`gate-security-stopped-app-owner-replacement-undetected` (shipped).
