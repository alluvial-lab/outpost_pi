# Outpost-Pi — Cockpit (Flutter Desktop)

Before editing or reviewing `cockpit/`, read the stack reference in [`../.agents/skills/flutter-desktop-cockpit/SKILL.md`](../.agents/skills/flutter-desktop-cockpit/SKILL.md).

Outpost-Pi's **desktop** client (macOS first). A multi-pane GUI over the Pi engine:
projects on the left, agents in the center, file tree on the right. Each agent is a
local `pi --mode rpc` process that the app spawns and drives. Through its
extension-loaded RPC sessions, Cockpit also exposes relay controls and mobile
pairing; cryptography remains extension-owned. It is the local counterpart to `app/`
(the remote gateway). Reference plan:
[`../plan/37-desktop-cockpit.md`](../plan/37-desktop-cockpit.md).

## Current scope (post-refactor: workspace projection + remote control)

The MVP phase was surpassed by the *bold-refactor* (cockpit-workspace-projection,
generated-protocol, transcript-event-log). Cockpit is now a **workspace document +
projections**: the workspace is a pure `WorkspaceDocument` (`LeafPane`/
`SplitPane`, multiple tabs/sessions), and every agent is an `AgentSessionProjection`
derived from `pi --mode rpc` state — the UI consumes immutable projections, not
direct mutable fields. Workspace mutations go through pure *command transforms*
(`WorkspaceDocumentCommands` → `WorkspaceCommandResult`) with a single reducer
(`CockpitViewModel._applyWorkspaceCommand`). Remote-control surfaces use three
distinct paths: (1) **structured relay overlay commands** (`relay_on`/`off`/`toggle`/`status`,
`rename`) ride the cockpit-control schema over a live RPC session; (2) **Settings**
relays through the CLI adapter and reads paired devices from `peers.json`; (3)
**pairing and revocation** run as dedicated ephemeral RPC prompt sessions. The pi
extensions remain loaded and own all cryptography — Cockpit performs no crypto itself.

Settled decisions (plan 37, 2026-06-05; revised in bold-refactor):

| # | Decision |
|---|---|
| **A** | Code lives here in `cockpit/` (not inside `app/`). Future reuse with `app/` via `packages/pi_core` — **not yet extracted** |
| **B** | Spawn `pi --mode rpc` **with extensions** (outpost-pi loaded for command discovery + control). `noSession`/`noExtensions` default to `false` (see `lib/app/core/env.dart`) |
| **C** | **Own** spawn — do not reuse the plan 26 supervisor (which is fire-and-forget without streaming) |

## Stack

- Flutter desktop / Dart (same major as `app/`)
- Platform: **macOS first** (Windows/Linux possible through Flutter, untested)
- DI + routing + state: **`flutter_modular`** (v7). Every feature is a module
  (`createModule`) that declares **its own routes + binds**; page-scoped state
  through `provide`/`addChangeNotifier` (over `ChangeNotifier`), app-scoped state
  (theme/font) through `ModularApp.provide`. Replaces `provider` + `auto_injector` +
  `go_router`.
- UI state consumption: `context.watch/read/select`, `Consumer`/`Selector`
  (re-exported by `flutter_modular` — same API as `provider`).
- Typed result: `Result<T, E>`
- Subprocess: `dart:io` `Process.start` (spawning `pi --mode rpc`)
- Native menu: `PlatformMenuBar`

> **Intentionally diverges from `app/`**: Cockpit is organized in **vertical
> feature slices** (`lib/app/<feature>/{domain,data,ui}`), not global layers. The
> motivation was to eliminate the `router.dart`/`dependencies.dart` god classes and
> keep every feature self-contained (it grows without editing shared files). The
> mobile `app/` continues using layered architecture — do not mirror one in the other.

## Commands

The Flutter SDK and pub cache live in the repository (not in `/opt` or `/tmp`).
Set `PUB_CACHE` and use the binary in `.tools/flutter`. For Cockpit, `pub get`
requires `--offline` because 3 git-overridden dependencies (`gpt_markdown`,
`kyroon_pty`, `xterm` from `github.com/jacobaraujo7/*`) cannot clone online — the
global git config rewrites https→ssh and there is no SSH key in this sandbox; the
bare mirrors in `.pub-cache/git/cache/` resolve offline. See
[`../.agents/skills/flutter-desktop-cockpit/SKILL.md`](../.agents/skills/flutter-desktop-cockpit/SKILL.md)
for why.

```bash
cd cockpit
export PUB_CACHE=~/projects/outpost_pi/.pub-cache
~/projects/outpost_pi/.tools/flutter/bin/flutter pub get --offline   # Cockpit requires --offline
~/projects/outpost_pi/.tools/flutter/bin/flutter analyze              # must pass with zero issues
~/projects/outpost_pi/.tools/flutter/bin/flutter test
~/projects/outpost_pi/.tools/flutter/bin/flutter run -d macos
~/projects/outpost_pi/.tools/flutter/bin/flutter build macos
```

- `dart format .` — formats (or `~/.tools/flutter/bin/cache/dart-sdk/bin/dart format .`)

## Architecture — vertical feature slices

Everything lives under `lib/app/`. Every **feature** is a self-contained mini-app
with its own `domain/ data/ ui/` layers and **one module** (`<feature>_module.dart`)
that declares that feature's routes and binds. `app/core/` contains only what is
cross-cutting (used by 2+ features). **Read [`lib/app/CLAUDE.md`](lib/app/CLAUDE.md)
(feature/module conventions) and [`lib/app/core/CLAUDE.md`](lib/app/core/CLAUDE.md)
(what is kernel) before editing.**

```
lib/
├── main.dart                 # async bootstrap (Hive/boxes/config/notifier) + runApp(ModularApp)
└── app/
    ├── app_module.dart       # root: composes core + features (composition only)
    ├── app_widget.dart       # AppRoot: ShadcnApp.router + watch<SettingsController>
    ├── core/                 # cross-cutting kernel (module WITHOUT path → root-owned binds)
    │   ├── core_module.dart  # shared binds (PiSpawnConfig)
    │   ├── routes.dart  env.dart  app_intents.dart
    │   ├── domain/  data/    # markers (Service/Disposable), Result, shared contracts/impls
    │   └── ui/               # themes/  widgets/  file_icons/  settings_controller.dart (app-scoped)
    ├── cockpit/              # FEATURE: the shell (projects | panes/agents/terminal | files)
    │   ├── cockpit_module.dart   # path '/', binds + route('/', provide: Cockpit/Setup/Update VMs)
    │   └── domain/  data/  ui/   # ui/ = cockpit_page + viewmodels/ session/ states/ widgets/
    └── settings/             # FEATURE: connectivity + daemon agents + schedules (cron)
        ├── settings_module.dart  # path '/settings', binds + route('/', provide: Connectivity/Daemons/Cron VMs)
        └── domain/  data/  ui/
```

Dependency flow **inside each feature** (and core):

```
ui ──► domain ◄── data
        ▲
   <feature>_module.dart   (composes: registers binds + declares route + provides ViewModels)
```

- `domain/` (of every feature and core) does **not** import `data/`, `ui/`, or modules.
- `data/` implements `domain/` contracts; it never imports from `ui/`.
- `ui/` consumes `domain/` through page-scoped ViewModels — it never calls `data/` directly.
- `<feature>_module.dart` is the only place that knows the feature's three layers.
- A feature **may import from `core/`, never from another feature**; `core/` does not
  import from any feature. (E.g. `SupervisorClientImpl`, which serves daemons **and**
  cron, and global `SettingsController` belong where they are shared, not in a tab.)

## Conventions

- **Naming**: `snake_case.dart` files, `PascalCase` classes, `PascalCase` widgets
- **Imports**: relative within the same feature; absolute through `package:cockpit/...`
  when crossing features or layers
- **Barrel files**: each feature/module may expose a `<name>.dart` aggregating its
  public symbols; external consumers import only the barrel
- **Async**: prefer typed `Future`/`Stream`; avoid `dynamic` (the RPC event stream
  is typed in `domain/`, never raw `Map<String, dynamic>` in `ui/`)
- **Errors**: `Result<T, E>` or typed exceptions; never generic production `catch (e)`
- **ViewModels**: page-scoped `ChangeNotifier`, provided in the route's `provide:`
  (`s.addChangeNotifier<T>(…)`) **inside `<feature>_module.dart`**; pages never
  instantiate a ViewModel — always `context.watch/read/select`. They are created
  when the route mounts and `dispose()`-ed on exit. App-global state (theme/font =
  `SettingsController`) lives in `ModularApp.provide`, above `ShadcnApp`.
- **`.new` injection** (rule): register binds and ViewModels with the **constructor
  tear-off** (`addChangeNotifier<Foo>(Foo.new)`, `addLazySingleton<Bar>(Bar.new)`)
  and let `auto_injector` resolve parameters through the graph. **Do not** write
  `() => Foo(inject<A>(), inject<B>())` when `Foo.new` resolves it. Post-construction
  (`init()`/`check()`) runs in the page's `initState`, not chained in the factory.
  Two cases require a **named type** to follow `.new` (the `auto_injector` parameter
  parser uses regex on the constructor's `toString`):
  - **factory dependency** ("create a new X for each use"): use a **factory
    interface** (`abstract class XFactory { X create(); }`, implementation in `data/`),
    **not** `X Function()` — the parser breaks on `=>` and merges two consecutive
    factory parameters. See `PairingGatewayFactory` + `ConnectivityViewModel`.
  - **multiple ambiguous primitives** (multiple `String`): replace them with an
    injectable **value object** (e.g. `UpdateTarget` in `cockpit_module`).
- **Theme**: never hardcode `Color(0x…)` / `TextStyle(fontFamily:…)`; read through
  `context.colors.<token>` / `context.typo.<style>` (barrel `app/core/ui/themes`)

## Critical rule: `BuildContext` in asynchronous code

Accessing `context` after an `await` (or inside `.then/.onSuccess/.flatMap/.whenComplete`)
can crash with `Null check operator used on a null value` if the widget has already
been unmounted. The `use_build_context_synchronously` lint **does not detect** chained
callbacks — prevention is manual.

```dart
// CORRECT — await + guard
final result = await viewModel.spawnAgent();
if (!mounted) return;           // in StatefulWidget
// if (!context.mounted) return; // in StatelessWidget
context.useContextSomehow();
```

```dart
// WRONG — context inside asynchronous callback
await viewModel.spawnAgent().onSuccess((_) {
  context.useContextSomehow(); // CRASH if unmounted
});
```

> Never use `context` inside `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()`, or `.whenComplete()`. Always convert to `await` + guard.

## Do NOT

- Edit files outside `cockpit/`
- Reuse the plan 26 supervisor (decision C — own spawn)
- Implement cryptography manually — the extension owns pairing keys and
  owner-channel cryptography
- Commit `build/`, `.dart_tool/`, `macos/Pods/`
- Add a dependency without registering it in plan 37
- Mix responsibilities between layers/features — when in doubt, read
  [`lib/app/CLAUDE.md`](lib/app/CLAUDE.md) and the target feature's `domain/data/ui`
- Import from one feature into another, or from `core/` into a feature — only
  feature→core is allowed (see dependency flow above)
- Recreate god classes: **do not** centralize routes or binds in one file — every
  feature declares its own in `<feature>_module.dart`

## Orchestrated mode

If you receive a prompt starting with `[ORCH:<task-id>]`, read
[`../.orchestration/INSTRUCTIONS.md`](../.orchestration/INSTRUCTIONS.md) before
any other action. That marker indicates another agent is coordinating the work
and has specific rules (where to write the result, do not commit, etc.).
