# `lib/app/core/` — cross-cutting kernel

What is **shared by 2+ features** or is app-global lives here. It is not a
feature: `core_module.dart` is a `createModule` **without `path`** → its bindings
are root-owned (live for the entire app, never disposed).

> **Golden rule**: `core/` **does not import from any feature**. Features
> import from `core/`, never the other way around. If something in core needs a feature,
> it is not core — it belongs in the feature.

## What lives here

```
core/
├── core_module.dart   # root-owned bindings: PiSpawnConfig + Pairing/RevokeGatewayFactory
├── routes.dart        # RoutePaths (path consts; avoids magic strings)
├── env.dart           # PiSpawnConfig (resolves the pi binary + args)
├── app_intents.dart   # global shortcut bridge (composer focus)
├── domain/
│   ├── contracts/     # markers: Service/Disposable/UseCase; settings_store;
│   │                  #   pairing_gateway, revoke_gateway (+ factories)
│   ├── entities/      # app_settings (preferences); pair_event
│   ├── exceptions/    # relay_error
│   └── result.dart    # Result<T, E>
├── data/              # shared utils plus storage/: atomic JSON factory,
│   │                  #   paths, legacy migration; repositories/json_settings_store
│   └── relay/         # ephemeral_pi_rpc + pairing/revoke gateway impls
└── ui/
    ├── settings_controller.dart  # APP-SCOPED (theme/font) — built in main,
    │                             #   provided in ModularApp.provide (not in a route)
    ├── themes/        # dark theme; context.colors / context.typo / syntax
    ├── widgets/       # widgets reused by +1 feature (hover_tap, app_menu,
    │                  #   code_highlight, window_controls)
    └── file_icons/    # icon map by file type
```

## Criterion: core vs feature

- Used by **only one** feature → goes in the feature (`app/<feature>/...`).
- Used by **two or more** (or is app-global) → core.
- **Exception (DI)**: a feature-level binding (module with `path`) **cannot see
  core** in `auto_injector` resolution — only page-scoped `provide` and core can
  see it. Therefore, a binding that resolves a core dependency **through its
  constructor** belongs here (root-owned) even if only one feature uses it. This is
  the case for `Pairing/RevokeGatewayFactory`: they receive `PiSpawnConfig` in their
  constructor, so they stay in core with config, and `ConnectivityViewModel`
  (settings, page-scoped) injects them.
- E.g., `SupervisorClientImpl` serves daemons **and** cron (the same instance under two
  contracts) → it lives in `settings/data` because both belong to the *settings* feature;
  `SettingsController` (theme read by the shell **and** edited in settings) and
  `PiSpawnConfig` (Cockpit RPC **and** ephemeral settings Pi) are core.

## Theme

All color/typography comes from `themes/` through `context.colors.<token>` /
`context.typo.<style>` (barrel `themes/themes.dart`). Never hardcode `Color(0x…)`
or `TextStyle(fontFamily:…)` in a widget.
