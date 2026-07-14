# `config/` Layer

## Purpose

Own all application orchestration decisions: bootstrapping, dependency
configuration (`auto_injector`), environments, keys, and global integrations.
This layer knows every other layer — it is the only place permitted to do so.

## Must do

1. **Declare bindings**: every shared dependency originates here through
   `injector.add...`. Repositories, services, and ViewModels all go through the
   registry.
2. **Use automatic injection**: prefer passing the constructor reference
   (`MyClass.new`) rather than instantiating manually. `AutoInjector` resolves
   parameters itself.
3. **Isolate setup**: SDK, log, route, and global-theme initialization belongs
   in clearly named functions (`setupDependencies`, `disposeDependencies`,
   `bootstrap`).
4. **Rely on contracts**: use only interfaces exposed by `domain/`, `data/`
   (services), and `ui/` (ViewModels) — do not create business logic.
5. **Document switches**: environment variables and feature flags need a
   description in this file or in `.env.example`.

## Must not do

1. **Encode domain rules** — no calculation, validation, or business rule
   belongs here.
2. **Create manual singletons** — always use `AutoInjector` to control the
   lifecycle.
3. **Import widgets or pages** — remain independent of the `ui/` layer
   (except type declarations required to register ViewModels).
4. **Perform network calls** — configure clients, but do not consume services
   directly.

## Suggested structure

```
config/
├── dependencies.dart    # setupDependencies / disposeDependencies / ViewmodelProvider
├── env.dart             # --dart-define and feature-flag reading
├── theme.dart           # global ThemeData
└── utils/
    └── injector.dart    # CustomInjector — typed facade over auto_injector
```

## DI system — how to use it

The [`CustomInjector`](utils/injector.dart) facade wraps `auto_injector` with
layer-typed methods. Each method declares intent and binds the type to a domain
contract (`Service`, `Repository`, `UseCase`, `ViewModel`).

### Register dependencies

Everything is registered in `setupDependencies()` in
[`config/dependencies.dart`](dependencies.dart), in this order:

```dart
Future<void> setupDependencies() async {
  // 1. Ready instances (SDKs)
  _injector.addInstance<SharedPreferences>(await SharedPreferences.getInstance());

  // 2. Infrastructure services (lazy singleton + automatic disposal)
  _injector.addService<NetworkService>(NetworkServiceImpl.new);

  // 3. Utility factories (without a domain contract)
  _injector.addOther<Dio>(dioFactory);

  // 4. Repositories (implementation in data/, contract in domain/)
  _injector.addRepository<PairingRepository>(PairingRepositoryImpl.new);

  // 5. Use cases (new instance per call)
  _injector.addUseCase<PairWithPiUseCase>(PairWithPiUseCase.new);

  // 6. ViewModels (new instance per screen)
  _injector.addViewModel<HomeViewModel>(HomeViewModel.new);

  _injector.commit(); // prevents further registrations
}
```

### Lifecycle

- `addService` / `addRepository` → lazy singleton; `dispose()` is called when
  `disposeDependencies()` runs.
- `addUseCase` / `addViewModel` → plain `_injector.add(...)`: each `get`
  returns **a new instance**. Screen state never leaks between routes.
- `addInstance` → exactly the object provided, permanently.
- `addOther` → lazy singleton, **without** a dispose hook.

### How the ViewModel reaches the UI

`config/dependencies.dart` exports `ViewmodelProvider<T>` — a
`ChangeNotifierProvider` that asks the injector for a new ViewModel instance
when the route is mounted. Composition in `routing/router.dart` is the
**only** place where ViewmodelProviders are declared:

```dart
GoRoute(
  path: routePaths.home,
  builder: (_, __) => MultiProvider(
    providers: [
      ViewmodelProvider<HomeViewModel>(),
      ViewmodelProvider<HomeFilterViewModel>(),
    ],
    child: const HomePage(),
  ),
)
```

See `ui/CLAUDE.md` for consumption details.

## Vocabulary

- **Injector** — single source of truth for dependencies.
- **Binding** — contract that associates a concrete type with its provider in
  the injector.
- **Bootstrap** — application initialization sequence before `runApp`.
