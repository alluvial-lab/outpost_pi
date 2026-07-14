---
id: epic-rebrand-external-surfaces-no-default-relay
kind: feature
stage: drafting
tags: [rebrand, pi-extension, app]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Remove community relay default (no-default relay)

## Brief

Both clients hard-fallback to `kDefaultRelayUrl` (`relay-rp1.jacobmoura.work`,
Jacob Moura's infrastructure) when no explicit relay is configured. The
community relay is being retired from the product — Outpost-Pi becomes
local-relay-only. This feature removes the silent default and makes
"unconfigured" an actionable, surfaced state rather than a hidden fallback to
a dead third-party host.

This is the design-bearing slice of the epic: it changes onboarding UX, not
just constants. The "Community relay" card in onboarding must go, and
self-hosted relay selection becomes mandatory.

## Epic context
- Parent epic: `epic-rebrand-external-surfaces`
- Position in epic: the only UX-bearing feature; F2 (hostname migration) and
  F3 (rp-s3 retirement) are independent mechanical features that run in
  parallel. This feature owns the `relay-rp1.jacobmoura.work` hostname's
  removal; F2 owns `outpost-pi`/`remote-pi` hostnames; F3 owns `rp-s3`.

## Foundation references
- `pi-extension/src/config.ts` — `kDefaultRelayUrl`, `resolveRelayUrl()`
  precedence (env → config → default)
- `app/lib/data/transport/relay_config.dart` — mirror: `kDefaultRelayUrl`,
  `resolveRelayUrl(prefs)`
- `app/lib/ui/onboarding/widgets/relay_step.dart` — the "Community relay"
  card with `footer: kDefaultRelayUrl`
- `app/lib/ui/onboarding/viewmodels/onboarding_viewmodel.dart` —
  "empty = default" logic in relay validation
- `app/lib/ui/onboarding/states/onboarding_state.dart` — `RelayChoice` enum
  (`community`, `custom`)
- `app/lib/ui/settings/settings_page.dart` + `settings_viewmodel.dart` —
  settings relay field defaults to `kDefaultRelayUrl`
- `app/lib/pairing/pair_request_flow.dart`, `app/lib/config/dependencies.dart`,
  `app/lib/data/mesh/mesh_client.dart` — callers of `resolveRelayUrl`

## Design decisions (inherited from epic)
- **No default relay.** Empty/absent relay URL means "not configured." Both
  clients surface an actionable state ("set a relay via /outpost-pi
  set-relay" / onboarding forces selection) rather than silently falling
  back.

## What this feature does NOT cover
- Migrating the site/homepage hostname (`outpost-pi.jacobmoura.work`) —
  that's F2 (`epic-rebrand-external-surfaces-hostname-migration`).
- Retiring rp-s3 — that's F3 (`epic-rebrand-external-surfaces-retire-rp-s3`).

<!-- The design pass (`/agile-workflow:feature-design`) fills in interfaces,
signatures, and test approach. -->
