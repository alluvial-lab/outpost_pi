---
id: story-capture-delivery-app-upload
kind: story
stage: implementing
tags: [app]
parent: feature-debug-capture-delivery
depends_on: ['story-capture-delivery-protocol-extension']
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Capture upload: app quick action + chunked upload client + progress UX

Per feature design. "Send debug logs" row in quick-actions (icon+label per
Phosphor tokens; 48dp hit region; regenerate the quick-actions goldens).
Client: reads latest closed ring (fallback: snapshot active ring), base64
chunks ≤8 KiB decoded, begin/chunk/end per generated protocol, progress
(0-100, indeterminate while reading), delivered state shows the ack'd path,
retry restarts from scratch (no resume v1), typed error surfacing. Widget
tests with fake transport: chunk sequencing, mid-chunk failure → retry
works, oversize ring → friendly refusal, delivered state. `flutter
analyze` + full suite green.
