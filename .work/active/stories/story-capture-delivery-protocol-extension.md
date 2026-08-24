---
id: story-capture-delivery-protocol-extension
kind: story
stage: done
tags: [pi-extension, protocol]
parent: feature-debug-capture-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-25
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

## Implementation

- Added schema-owned `capture_upload_begin` / `capture_upload_chunk` /
  `capture_upload_end` and typed `capture_upload_ack` /
  `capture_upload_error` variants, including generated upload limits and
  regenerated Dart + TypeScript projections.
- Added a lifecycle-owned extension reassembler with strict sequencing,
  base64/cap checks, SHA-256 and JSONL validation, one-upload admission,
  stale/detach GC, containment-checked atomic writes, typed replies, and a
  visible `outpost-pi:debug-capture-delivered` Pi session note.
- Added boundary fixtures and tests for success, caps, sequence/checksum
  failures, traversal-shaped ids, atomic temp cleanup, abandon GC, detach,
  invalid capture, one-in-flight admission, and exactly-once note emission.
- Verification: `corepack pnpm typecheck`, `corepack pnpm test`, and
  `corepack pnpm build` pass from `pi-extension/`.
