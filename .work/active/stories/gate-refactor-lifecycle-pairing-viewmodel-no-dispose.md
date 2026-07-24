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
Add disposal/generation fencing, close transient resources during disposal, and revalidate the generation after every await before assigning, adopting, or emitting.

**Absorbs `gate-patterns-inconsistency-pairing-viewmodel-generation-fence`
(merged 2026-07-24, operator-directed):** the async-gap/channel-install
divergence at `pairing_viewmodel.dart:81-122` must be brought into
conformance with the documented `generation-fenced-async-ownership` pattern
as part of this fix — one change, both acceptance sets.

## Acceptance
- PairingViewModel gains a dispose() path that closes `_transport` and `_liveChannel`; route removal mid-pairing leaks no transport or channel.
- A lifecycle generation fences every async gap in the pairing attempt (`pairing_viewmodel.dart:81-122`): after each await, the generation/disposed state is revalidated before assigning, adopting the channel, or emitting UI state — conforming to the `generation-fenced-async-ownership` pattern.
- A stale-generation or disposed ViewModel never adopts a channel or emits state.
- Tests cover disposal mid-pairing and stale-generation completion.
