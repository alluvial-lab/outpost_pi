---
id: story-harvest-app-working-idle-reconciliation
kind: story
stage: implementing
tags: [app, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-15
updated: 2026-08-15
---

# Working-state reconciliation: authoritative idle beats stale transcript.working

Upstream `12ef2956` (clear new-session state + reconcile stale working state
from room metadata). The session-reset half is already covered by our
`sync_service.dart:667-700` reset block. The remaining gap: on room change we
only rebind/sync (`sync_service.dart:752-777`), and an idle room still lets
stale `transcript.working` win in projection
(`app/lib/domain/transcript/transcript_projection.dart:85`) — so a working
spinner can survive a session that ended while disconnected.

## Direction

Port the authoritative-idle reconciliation INTO the canonical projection
model — when room/session metadata says idle, the projection must converge
`working` false regardless of the last transcript frame. Do NOT port
upstream's boolean dance directly; their architecture predates our
projection. Mind the known failure modes already fixed here
(`story-fix-working-flag-stuck-after-session-shutdown`,
`story-fix-onconnected-clobbers-working-midturn`, both v0.4.0): the
reconciliation must not clobber a genuine mid-turn working state
(`onConnected` lesson) — metadata idle is authoritative only for the session
it describes, keyed by session identity.

## Verification

`flutter analyze && flutter test --exclude-tags e2e`; tests: idle metadata
after disconnect clears stale working; live mid-turn working survives a
reconnect-sync that carries older metadata (generation/identity keyed).
Cite upstream sha in the commit message.
