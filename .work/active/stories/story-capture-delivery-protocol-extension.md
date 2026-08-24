---
id: story-capture-delivery-protocol-extension
kind: story
stage: implementing
tags: [pi-extension, protocol]
parent: feature-debug-capture-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Capture upload: schema, codegen, extension handler, session note

Per feature design (read parent). Extend `protocol/schema/outpost-pi.schema.json`
+ regenerate (`tools/protocol-codegen`) BOTH sides in one commit. Extension:
reassembly buffer per upload id, caps (8 KiB/chunk decoded, 2 MiB total,
1 in-flight), strict sequence, sha256 check on end, atomic tmp+rename write
to `<room cwd>/debug/app-capture-<iso>-<idtail>.bin`, path-containment
guard, GC (timer + channel detach), typed ack/errors, session-visible
delivered note. Unit tests in pi-extension suite: happy path, oversize,
bad sequence, checksum mismatch, traversal attempt, abandon+GC, note
emitted once. Run `corepack pnpm typecheck && test && build`.
