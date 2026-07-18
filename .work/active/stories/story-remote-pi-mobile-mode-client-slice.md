---
id: story-remote-pi-mobile-mode-client-slice
kind: story
stage: done
tags: [app, pi-extension, workflow]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: [story-remote-pi-android-build-smoke]
release_binding: null
gate_origin: null
created: 2026-06-27
updated: 2026-07-18
---

# Add one remote-pi client-side mobile-mode control slice

## Brief

Only after the SNC-root plain-text `story-pi-mobile-mode-toggle` path and local Android build path are known,
add a minimal in-app control for mobile mode if real use shows text controls are insufficient.

## Candidate slice

Add a Quick Action or lightweight input affordance that sends the same semantic control as the
plain-text extension path (`mobile on`, `mobile off`, `mobile status`) without requiring slash-command
support.

## Acceptance

- The in-app control toggles mobile mode in the paired Pi session.
- It does not require broad protocol redesign.
- The implementation records whether the right upstream path is a PR to `remote-pi` or a private fork carry.

## Disposition (2026-07-18)

**Closed as a conditional provenance checkpoint; no implementation.** The local Android build/pair path is now
known, but the second condition was not demonstrated: the app's existing plain-text chat input has not proved
insufficient for the semantic `mobile on`, `mobile off`, and `mobile status` controls. No real-use report or
failure evidence justifies adding a dedicated Quick Action, and this fork has no separate mobile-mode wire
contract to extend.

`feature-mobile-native-session-process-control` is related because it is designing first-class mobile session
and process actions, but it does not silently claim mobile-mode semantics. If real use later shows text control
is inadequate, reopen this as a small, evidence-backed app action and decide its protocol/upstream disposition
then. The current fork remains the source of the shipped stale-context fix; this checkpoint introduces no new
upstream or private-carry change.
