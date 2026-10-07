---
id: idea-pi-104-peer-deps-host-packages
created: 2026-10-06
updated: 2026-10-06
tags: [pi-extension, packaging, pi-compat]
---

# pi 1.0.4: declare host-provided packages as peerDependencies

Under pi 1.0.4 the extension loader warns that `outpost-pi` (this repo's
`pi-extension/package.json`) declares host-provided packages in
`dependencies` instead of `peerDependencies`:

- `@earendil-works/pi-coding-agent` — currently pinned `0.84.3`
- `typebox` — currently `^1.3.13`

Risk is real, not cosmetic: a regular dependency resolves the extension its
own module instance — here even a *different version* than the running host
(pinned 0.84.3 vs the fleet's pi 1.0.4) — so host types crossing the
boundary fail `instanceof`/identity checks and the SDK surface silently
forks. Same warning fires for the third-party `@gotgenes/pi-subagents`
(upstream's to fix; operator-gated report, not ours to patch).

Scope when promoted:

1. Move both to `peerDependencies` with a range that accepts the hosts we
   actually support (decide `>=0.84.3` vs an upper bound from the SDK
   surface we consume); mirror them in `devDependencies` so typecheck /
   vitest / build still resolve locally.
2. Verify the fleet's install path (local-path package in
   `~/.pi/agent/settings.json`) and CI under pnpm 11.9.0 strict peer
   resolution — the just-landed pnpm unification (797d861b4) interacts
   here; check `pnpm-workspace.yaml` overrides posture.
3. Confirm the loader warning is gone under pi 1.0.4 and the running
   extension still typechecks/executes against the host's module instance.

Provenance: fleet CHANGELOG 2026-10-06 anomaly entry (pi 0.87.1 → 1.0.4
upgrade night); surfaced by the fleet-root session.
