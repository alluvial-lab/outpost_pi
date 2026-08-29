---
id: gate-refactor-lifecycle-bare-session-new-exit-teardown
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: refactor
created: 2026-08-29
updated: 2026-08-29
---

# Bare `/new` exit bypasses lifecycle-owned runtime teardown

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Relevance
Release-relevant

## Location
`pi-extension/src/index.ts:3297`

## Issue
The no-context bare `/new` branch calls `process.exit(EXIT_FRESH_SESSION)` directly without invoking the lifecycle-owned runtime disposal path, so owner channels, relay/mesh resources, and the room's working state can bypass graceful teardown.

## Fix
Route this terminal fallback through the lifecycle owner so runtime resources are disposed and `working=false` is published before the bounded exit; retain the exit as the fail-closed fallback only after cleanup ownership has been established.

## Resolution (2026-08-29)
The bare `/new` path now enters `FreshSessionShutdownCoordinator` with the same synchronous owner-delivery fence, admitted-delivery drain, runtime disposal, and exit-code-42 deadline as wrapper/daemon mode. The lifecycle-owned runtime teardown detaches owner channels, converges the session projection, and closes relay/mesh resources before termination; managed wrapper/daemon staging remains unchanged. The regression test observes detached owners, disposed state, relay close, and exit 42 ordering.

Verified with `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` from `pi-extension/`.
