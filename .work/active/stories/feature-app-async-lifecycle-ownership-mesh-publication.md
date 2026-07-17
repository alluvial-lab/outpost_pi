---
id: feature-app-async-lifecycle-ownership-mesh-publication
kind: story
stage: implementing
tags: [app, lifecycle]
parent: feature-app-async-lifecycle-ownership
depends_on: [feature-app-async-lifecycle-ownership-connection-persistence]
release_binding: null
gate_origin: null
created: 2026-07-17
updated: 2026-07-17
---

# Own and retry mesh publication after peer mutation

## Checkpoint

Implement Unit 6 from the parent feature: carry peer mutation intent through the
synchronous storage hook, inspect every typed publish result inside
`MeshSyncService`, coalesce concurrent mutation publishes, and queue transient
retry without pulling over pending local state.

## Finding coverage

- `gate-refactor-lifecycle-peer-mesh-publish-dropped`

## Required behavior

- `PairingStorage` emits typed `PeerMutationKind.upsert/delete`; silent
  pull/apply methods remain hook-free.
- DI attaches `publishAfterPeerMutation` directly and discards no future.
- A mutation during publish causes one follow-up publish.
- Transient/exception outcomes remain pending and retry through one owned timer;
  permanent typed outcomes diagnose and stop.
- Normal pull defers behind pending local publication; conflict rebase retains a
  private allowed pull.
- Delete intent safely permits last-peer `members=[]`, allowing Settings to
  remove its duplicate explicit publish and optional mesh dependency.
- Disposal cancels retry/drain lifecycle state.

## Acceptance evidence

- [ ] Tests cover every `MeshPublishResult` disposition and unexpected throw.
- [ ] Tests cover concurrent mutation coalescing, transient retry, permanent
      no-retry, pull deferral, and disposal.
- [ ] Last-peer revoke publishes empty membership once; pull/apply never
      re-enters publication.
- [ ] Targeted mesh/storage/settings tests and `flutter analyze` pass.
