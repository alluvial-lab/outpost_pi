---
id: gate-refactor-lifecycle-pairing-viewmodel-no-dispose
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# Pairing ViewModel can outlive its route with an open transient channel

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart:40`

## Issue
PairingViewModel owns _transport and _liveChannel but has no dispose() path, allowing route removal during pairing to leak the transport and later adopt or emit from a disposed ViewModel.

## Fix
Add disposal/generation fencing, close transient resources during disposal, and revalidate the generation after every await before assigning, adopting, or emitting. (Overlaps gate-patterns-inconsistency-pairing-viewmodel-generation-fence — reconcile together.)
