# `ui/` layer

## Purpose

Deliver the user's visual and interactive experience, consuming ViewModels and
use cases to reflect application state by feature.

## Must do

1. **Organize by feature** — each directory represents a complete flow
   (page, states, viewmodels, widgets).
2. **Delegate business logic** — ViewModels call use cases and only
   interpret results for screen state.
3. **React through `ChangeNotifier` + `Consumer`** — keep the
   UI → ViewModel → UseCase → ViewModel → UI loop clear and unidirectional.
4. **Cultivate small widgets** — prefer `StatelessWidget`, with
   `widgets.dart` exporting feature components (barrel file).
5. **Apply consistent visual language** — all theming (colors, typography,
   font) lives in [`core/themes/`](core/themes/themes.dart). **Never** hardcode
   `Color(0x…)`, `Colors.*`, or `TextStyle(fontFamily: …)` in a widget: read through
   `context.colors.<token>` and `context.typo.<style>` (import the barrel
   `package:app/ui/core/themes/themes.dart`). New semantic colors go in
   `AppColors` (dark + light), text styles in `AppTypography`, and the font family
   is the `kMonoFamily` constant. Permitted exceptions: theme-independent
   scrims/overlays (`Colors.black.withValues(...)` such as `barrierColor`,
   overlays over camera/photo, solid red destructive-action background).
6. **Consume ViewModels through Provider** — always through `context.watch<T>()`,
   `context.read<T>()`, or `context.select<T, R>()`. **Never** instantiate
   ViewModels directly in the page.
7. **Register ViewModels in `config/dependencies.dart`** — using
   `_injector.addViewModel<T>(T.new)`.
8. **Add `ViewmodelProvider<T>()` in `routing/router.dart`** in the
   corresponding route definition.

## ViewModel — the base state class

Every ViewModel extends [`ViewModel<T>`](core/viewmodel/viewmodel.dart), which is
a `ChangeNotifier` with **a single immutable state field** and a single
verb to modify it (`emit`). State lives in a sealed class in the feature's
`states/` directory.

```dart
// ui/pairing/states/pairing_state.dart
sealed class PairingState {
  const PairingState();
}

final class PairingIdle extends PairingState {
  const PairingIdle();
}

final class PairingScanning extends PairingState {
  const PairingScanning();
}

final class PairingPaired extends PairingState {
  const PairingPaired(this.deviceId);
  final String deviceId;

  @override
  bool operator ==(Object other) =>
      other is PairingPaired && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

final class PairingError extends PairingState {
  const PairingError(this.message);
  final String message;
  // ... == / hashCode
}
```

```dart
// ui/pairing/viewmodels/pairing_viewmodel.dart
class PairingViewModel extends ViewModel<PairingState> {
  PairingViewModel(this._pairWithPi) : super(const PairingIdle());

  final PairWithPiUseCase _pairWithPi;

  Future<void> startScan() async {
    emit(const PairingScanning());
    final result = await _pairWithPi();
    result.fold(
      (device) => emit(PairingPaired(device.id)),
      (error) => emit(PairingError(error.message)),
    );
  }
}
```

`emit` only fires `notifyListeners()` if the new state is `!=` the current one —
therefore states need correct `==` / `hashCode` (use `equatable` or
write them manually). This prevents unnecessary rebuilds.

## How the UI consumes the ViewModel

Pages **never** instantiate the ViewModel — the `ViewmodelProvider<T>` declared
in `routing/router.dart` (see `config/CLAUDE.md`) already injects the instance into
the tree. The page accesses it through `context`:

```dart
class PairingPage extends StatelessWidget {
  const PairingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Reads + listens — rebuilds when state changes
    final viewModel = context.watch<PairingViewModel>(); // or .read() not to listen
    final state = viewModel.state;

    return Scaffold(
      body: switch (state) {
        PairingIdle() => _IdleView(onScan: viewModel.startScan),
        PairingScanning() => const _ScanningView(),
        PairingPaired(:final deviceId) => _PairedView(deviceId: deviceId),
        PairingError(:final message) => _ErrorView(message: message),
      },
    );
  }
}
```

To react to **only one part** of the state (optimization):

```dart
final isScanning = context.select<PairingViewModel, bool>(
  (vm) => vm.state is PairingScanning,
);
```

### Checklist when creating a feature

1. Create `states/<feature>_state.dart` (sealed class with `==`/`hashCode`).
2. Create `viewmodels/<feature>_viewmodel.dart` extending `ViewModel<TState>`.
3. Register in `config/dependencies.dart`:
   `_injector.addViewModel<FooViewModel>(FooViewModel.new);`
4. Bind the route in `routing/router.dart` inside `MultiProvider` with
   `ViewmodelProvider<FooViewModel>()`.
5. The page consumes it through `context.watch/read/select`.

## Critical rule: `BuildContext` in asynchronous code

Accessing `context` after an asynchronous operation can crash
(`Null check operator used on a null value`) if the widget has already been
disposed. The `use_build_context_synchronously` lint **does not detect** use of
`context` inside `.onSuccess()`, `.onFailure()`, `.flatMap()`, `.then()`,
or `.whenComplete()` — prevention is manual.

**In `StatefulWidget`** — always use `mounted` before `context`:

```dart
// CORRECT — await + mounted guard
final result = await viewModel.doSomething();
if (!mounted) return;
context.sendLog('done');

// CORRECT — avoid .onSuccess, prefer await
final result = await viewModel.doSomething();
final value = result.getOrNull();
if (mounted && value != null) {
  context.sendLog('done');
}
```

```dart
// WRONG — context inside .onSuccess without guard (lint does NOT detect)
await viewModel.doSomething().onSuccess((_) {
  context.sendLog('done'); // CRASH if widget is disposed
});

// WRONG — context inside .flatMap without guard
await viewModel.doSomething().flatMap(
  (_) => context.sendLog('done'),
);
```

**In `StatelessWidget`** — use `context.mounted`:

```dart
final result = await viewModel.doSomething();
if (!context.mounted) return;
context.sendLog('done');
```

**Summary rule**:

> Never use `context` inside `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()`, or `.whenComplete()`. Always convert to `await` + guard
> (`mounted` / `context.mounted`) before touching `context`.

## Must not do

1. **Duplicate domain rules** — no business validation or complex formatting
   here; delegate to the domain.
2. **Instantiate ViewModels directly** — never `MyViewModel()` inside
   pages; always obtain them through `context.watch/read/select`.
3. **Instantiate services directly** — use dependencies already injected through
   ViewModels.
4. **Mix responsibilities** — no networking or persistence logic inside
   widgets.
5. **Break feature isolation** — cross-feature imports go through barrel
   files or clear contracts.
6. **Use `context` in asynchronous callbacks** — see "Critical rule" above.

## Feature directory structure

```
feature/
├── states/              # sealed classes for feature state
│   └── feature_state.dart
├── viewmodels/          # ViewModels that orchestrate state
│   └── feature_viewmodel.dart
├── widgets/             # componentized local widgets
│   ├── widgets.dart     # barrel
│   └── feature_widget.dart
└── feature_page.dart    # main page (Entry Widget)
```

## Vocabulary

- **Feature Page** — entry point for the feature experience.
- **ViewModel** — guardian of UI state and commands (extends
  `ChangeNotifier`).
- **State** — model of what the screen can show (sealed class with cases
  such as `Loading`, `Ready`, `Error`).
- **Consumer / Selector** — listener that rebuilds the UI on each ViewModel
  change.
- **Widgets Barrel** — `widgets.dart` file that exposes the feature's local
  components.
