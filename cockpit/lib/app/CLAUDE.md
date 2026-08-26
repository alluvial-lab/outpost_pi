# `lib/app/` — vertical features + modules

Everything in the Cockpit lives here. Each **feature** is a self-contained mini-app;
`core/` is the cross-cutting kernel (see [`core/CLAUDE.md`](core/CLAUDE.md)).

## Feature anatomy

```
app/<feature>/
├── <feature>_module.dart   # feature routes + binds (createModule)
├── domain/                 # feature contracts (interfaces) + entities
├── data/                   # contract implementations (IO, processes, repos)
└── ui/
    ├── <feature>_page.dart # route entry widget
    ├── viewmodels/         # page-scoped ChangeNotifiers
    ├── widgets/            # local widgets (optional widgets.dart barrel)
    └── states/  session/   # feature-specific state structures (when present)
```

Dependency rule (per feature):
`ui ──► domain ◄── data`, with `<feature>_module.dart` composing all three.

- `domain/` does not import `data/`, `ui/`, or modules. Only Dart + `core/domain`.
- `data/` implements `domain/`; it never imports `ui/`.
- `ui/` consumes `domain/` through ViewModels — it **never** calls `data/` directly.
- A feature can import from `core/`; **never** from another feature.

## The feature module (`<feature>_module.dart`)

It is the heart: it replaces the old `dependencies.dart` (DI) and
`router.dart` (routes) god classes. Pattern (`flutter_modular` v7):

```dart
Module buildFooModule(/* async deps resolved in main */) => createModule(
  path: '/foo',                         // feature → routes flattened under /foo;
  register: (c) {                       //   no path = DI only (core case)
    c
      // feature binds: contract → impl. addInstance (ready instance),
      // addLazySingleton/add (constructor tear-off, auto-injected).
      ..addInstance<FooRepository>(FooRepositoryImpl(store))
      ..route(
        '/',                            // resolves to /foo
        transition: TransitionType.fade,
        // provide: PAGE-SCOPED state — born when route mounts, disposed when leaving.
        // Register through `.new` tear-off: auto_injector resolves parameters
        // from the binds above. init()/check() run in the page's initState.
        provide: (s) => s..addChangeNotifier<FooViewModel>(FooViewModel.new),
        child: (context, state) => const FooPage(),
      );
  },
);
```

- **DI lifecycle**: a bind in a module **with `path`** = feature-scoped (lives while
  the feature is on the stack). A bind in `core` (without `path`) = root-owned (entire app).
- **`.new` injection** (rule): register with the constructor tear-off (`Foo.new`) and
  let auto_injector resolve parameters through the graph — **do not** write
  `() => Foo(inject<A>(), inject<B>())`. `inject<T>()` is only for where there is no
  constructor (guards, callbacks). The auto_injector parameter parser is regex over the
  constructor's `toString`, so always use **named types**:
  - **factory** dependency ("a new X per use"): interface
    `XFactory { X create(); }` (impl in `data/`), **never** `X Function()` — `=>`
    breaks the parser and two consecutive factory params merge. See `PairingGatewayFactory`
    + `ConnectivityViewModel`.
  - **multiple ambiguous primitives** (`String`...): an injectable **value object**
    (e.g. `UpdateTarget`).
- **Async values** (opened state stores, `PiSpawnConfig`, version) are resolved
  before module registration and passed to `buildXModule(...)` factories —
  `register` is synchronous. Persistence opens only through the one
  `StateStoreFactory` owned by `main`.
- Register the feature in `app_module.dart` with `c.module(fooModule)`.

## ViewModels

Plain `ChangeNotifier`, **page-scoped** through `provide`. There is no longer a base
`ViewModel<T>` nor mandatory `states/` sealed class (it was aspirational, never used).
The page consumes through `context.watch<T>()` (rebuild), `context.read<T>()`
(callback), or `context.select<T,R>()` (granular rebuild). `Consumer`/`Selector`
also exist. **Never** instantiate a ViewModel in the page.

**App-global** state (theme/font = `SettingsController`) is not a feature concern: it lives
in `ModularApp.provide` (in `main`), above `ShadcnApp` → `context.watch` anywhere.

## Navigation

`context.pushNamed('/settings')` pushes modal-like (stays outside the URL; `pop`
returns). `context.navigate('/x')` replaces the stack base. `context.pop([result])`.
Paths in [`core/routes.dart`](core/routes.dart) (`RoutePaths`).

## Dialogs with their own state

`flutter_modular` has no ad-hoc tree provider. For a dialog controller
(e.g., pairing), create it at the call site, pass it through its **constructor** and consume
it with `ListenableBuilder` — and **dispose it at the end** (`ctrl.dispose()` after
`showDialog`), otherwise the ephemeral `pi --mode rpc` leaks. See
`settings/ui/pairing_dialog.dart`.

## Critical rule: `BuildContext` in asynchronous code

Accessing `context` after `await` (or inside `.then/.onSuccess/.flatMap/
.whenComplete`) crashes if the widget is disposed. The lint does not catch chained
callbacks — convert to `await` + guard (`if (!mounted) return;` /
`if (!context.mounted) return;`). Details in the [root CLAUDE.md](../../CLAUDE.md).

## Checklist — new feature

1. `mkdir app/<feature>/{domain,data,ui}`.
2. Contracts in `domain/contracts/`, implementations in `data/`, page + VMs in `ui/`.
3. `<feature>_module.dart`: registers binds + `route(...)` + VM `provide:`.
4. `c.module(<feature>Module)` in `app_module.dart` (passing async deps from `main`).
5. Path in `core/routes.dart` if navigated from elsewhere.
6. `flutter analyze` (zero issues) — catches cross-feature imports/layer violations.
