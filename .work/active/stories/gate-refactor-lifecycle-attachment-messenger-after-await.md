---
id: gate-refactor-lifecycle-attachment-messenger-after-await
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-20
---

# Guard attachment snackbar delivery after the async picker

## Library
lifecycle

## Rule
buildcontext-after-await

## Confidence
High

## Location
`app/lib/ui/chat/chat_page.dart:452`

## Issue
`_openAttach` captures a `ScaffoldMessengerState` from `context` before several awaits and uses it afterward without checking that the originating context is still mounted.

## Fix
Resolve the messenger only after the final await: check `context.mounted`, return when unmounted, then call `ScaffoldMessenger.of(context)` and deliver the attachment hint.

## Relevance
Release-relevant. The file is in the `v0.2.0` bundle.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent, so this finding has reduced review isolation.
