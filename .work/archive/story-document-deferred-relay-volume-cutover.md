---
id: story-document-deferred-relay-volume-cutover
status: superseded
superseded_by: "commit f1ee8ef (ops: relocate checkout remote_pi -> outpost_pi)"
kind: story
stage: implementing
tags: [rebrand, relay, docs, workflow]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-20
---

# Document the deferred relay-volume cutover

## Review origin

Important operational finding from the deep review of `feature-outpost-pi-identifier-convergence`.

## Problem

The operator-confirmed decision to retain the live `remote-pi-data` Docker volume until the separate checkout/cwd migration, then recreate the relay on `outpost-pi-data` and wipe the old volume, exists only in the transient feature body. Root `AGENTS.md` correctly keeps using the live legacy volume, while `relay/README.md` uses the canonical new-install name, but no durable runbook explains the intentional difference or the destructive cutover condition.

## Scope

- Add a concise durable note beside the live relay volume/run command in `AGENTS.md` explaining that `remote-pi-data` is intentionally retained until checkout/cwd migration.
- Record the cutover action: recreate the container with `outpost-pi-data`, allow mesh membership to re-register, then delete the old volume; no state-preserving migration is required by the confirmed decision.
- Make the destructive loss of the old mesh DB/log volume explicit enough that an operator does not delete it before the replacement relay is healthy.
- Preserve `relay/README.md`'s `outpost-pi-data` name for fresh installs.

## Acceptance criteria

- [ ] The durable deployment runbook explains why the live and fresh-install volume names differ.
- [ ] The cwd-migration trigger, replacement volume name, verification-before-delete order, and destructive wipe are explicit.
- [ ] Existing live commands continue to use `remote-pi-data` until that trigger occurs.
