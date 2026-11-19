---
id: story-mesh-broker-generation-split
kind: story
completed: 2026-10-09
tags: [pi-extension, bug]
created: 2026-10-09
updated: 2026-10-09
---

# Mesh broker generation split: rendezvous generations prevent restart-sweep partitions

Completed (`275066368`, cross-model review resolved `f68431380`). Eliminated multi-generation local mesh broker splits during mass restart sweeps via symlink rendezvous generations in `pi-extension`, with regression tests proving single-generation convergence and registration counts. Verified green across `corepack pnpm typecheck`, `vitest run` (1232 passed), and `corepack pnpm build`. Full pre-migration story record preserved in Git history at `fa32d6abb`.
