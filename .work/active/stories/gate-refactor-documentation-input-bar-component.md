---
id: gate-refactor-documentation-input-bar-component
kind: story
stage: done
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-25
---

# Convert the input composer contract to native dartdoc

## Library
documentation

## Rule
component-doc

## Confidence
High

## Location
`app/lib/ui/chat/widgets/input_bar.dart:36`

## Issue
The exported `InputBar` widget has more than a dozen behavior-bearing inputs for send/cancel, steering, queueing, voice, attachments, and compact layout, but its existing `// InputBar` prose is not dartdoc and therefore does not document the component in IDE or agent API surfaces.

## Fix
Replace the ordinary heading prose with intent-focused `///` dartdoc directly on `InputBar`, covering composer mode selection and ownership of optional voice/attachment effects without restating parameter types.

## Implementation

Replaced the historical heading with current-state dartdoc covering send,
queue, steering/cancellation, compact-height behavior, and voice/attachment
ownership; clarified the exported input contracts without repeating types.
