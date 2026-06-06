# Camada `ui/`

## Propósito

Entregar a experiência visual e interativa do Cockpit, consumindo ViewModels e use
cases para refletir o estado da aplicação por feature. No MVP: o shell de layout e
a visão de um agente (stream de eventos). **Panes/multiplexação ainda não** — ver
plano 37.

## Deve fazer

1. **Organizar por feature** — cada pasta representa um fluxo completo (página,
   states, viewmodels, widgets).
2. **Delegar lógica de negócio** — ViewModels chamam use cases e apenas
   interpretam resultados para o estado da tela.
3. **Reagir via `ChangeNotifier`** — manter o loop
   UI → ViewModel → UseCase → ViewModel → UI claro e unidirecional. O stream de
   `RpcEvent` chega ao ViewModel, que acumula e emite o novo state.
4. **Cultivar widgets pequenos** — preferir `StatelessWidget`, com `widgets.dart`
   como barrel da feature.
5. **Aplicar linguagem visual consistente** — todo tema (cores, tipografia) vive
   em `core/themes/`. **Nunca** hardcode `Color(0x…)`, `Colors.*` ou
   `TextStyle(fontFamily:…)` num widget: leia via `context.colors.<token>` e
   `context.typo.<estilo>` (import do barrel `package:cockpit/ui/core/themes/themes.dart`).
6. **Consumir ViewModels via Provider** — sempre via `context.watch<T>()`,
   `context.read<T>()` ou `context.select<T, R>()`. **Nunca** instancie ViewModels
   diretamente na página.
7. **Registrar ViewModels no `config/dependencies.dart`** — via
   `_injector.addViewModel<T>(T.new)`.
8. **Adicionar `ViewmodelProvider<T>()` no `routing/router.dart`** na rota correspondente.

## ViewModel — a classe base do estado

Todo ViewModel estende `ViewModel<T>` (`core/viewmodel/viewmodel.dart`), que é um
`ChangeNotifier` com **um único campo de estado imutável** e um único verbo para
alterá-lo (`emit`). O estado vive em uma sealed class na pasta `states/` da feature.

```dart
// ui/agent/states/agent_state.dart
sealed class AgentState {
  const AgentState();
}

final class AgentIdle extends AgentState {
  const AgentIdle();
}

final class AgentBooting extends AgentState {
  const AgentBooting();
}

final class AgentStreaming extends AgentState {
  const AgentStreaming(this.transcript);
  final List<RpcEvent> transcript;

  @override
  bool operator ==(Object other) =>
      other is AgentStreaming && other.transcript == transcript;

  @override
  int get hashCode => transcript.hashCode;
}

final class AgentCrashed extends AgentState {
  const AgentCrashed(this.message);
  final String message;
  // ... == / hashCode
}
```

```dart
// ui/agent/viewmodels/agent_viewmodel.dart
class AgentViewModel extends ViewModel<AgentState> {
  AgentViewModel(this._spawnAgent, this._sendPrompt) : super(const AgentIdle());

  final SpawnAgentUseCase _spawnAgent;
  final SendPromptUseCase _sendPrompt;

  Future<void> boot(Project project) async {
    emit(const AgentBooting());
    final result = await _spawnAgent(project);
    result.fold(
      (stream) => _listen(stream),         // acumula RpcEvent → AgentStreaming
      (error) => emit(AgentCrashed(error.message)),
    );
  }
}
```

`emit` só dispara `notifyListeners()` se o novo estado for `!=` do atual — por
isso states precisam de `==` / `hashCode` corretos. Isso evita rebuilds
desnecessários (importante: o stream RPC emite muito).

## Como a UI consome o ViewModel

Páginas **nunca** instanciam o ViewModel — o `ViewmodelProvider<T>` declarado em
`routing/router.dart` injeta a instância na árvore. A página acessa via `context`:

```dart
class AgentPage extends StatelessWidget {
  const AgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AgentViewModel>();
    final state = viewModel.state;

    return switch (state) {
      AgentIdle() => _IdleView(onBoot: viewModel.boot),
      AgentBooting() => const _BootingView(),
      AgentStreaming(:final transcript) => _TranscriptView(transcript),
      AgentCrashed(:final message) => _CrashedView(message: message),
    };
  }
}
```

Para reagir a **apenas um pedaço** do state (otimização — útil com stream barulhento):

```dart
final isStreaming = context.select<AgentViewModel, bool>(
  (vm) => vm.state is AgentStreaming,
);
```

### Checklist ao criar uma feature

1. Criar `states/<feature>_state.dart` (sealed class com `==`/`hashCode`).
2. Criar `viewmodels/<feature>_viewmodel.dart` estendendo `ViewModel<TState>`.
3. Registrar em `config/dependencies.dart`:
   `_injector.addViewModel<FooViewModel>(FooViewModel.new);`
4. Bindar na rota em `routing/router.dart` dentro de `MultiProvider` com
   `ViewmodelProvider<FooViewModel>()`.
5. Página consome via `context.watch/read/select`.

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após uma operação assíncrona pode crashar (`Null check operator
used on a null value`) se o widget já tiver sido desmontado. O lint
`use_build_context_synchronously` **não detecta** uso de `context` dentro de
`.onSuccess()`, `.onFailure()`, `.flatMap()`, `.then()` ou `.whenComplete()` — a
prevenção é manual.

```dart
// CORRETO — await + guard
final result = await viewModel.boot(project);
if (!mounted) return;            // StatefulWidget
// if (!context.mounted) return; // StatelessWidget
context.useContextSomehow();
```

```dart
// ERRADO — context dentro de .onSuccess sem guard (lint NÃO detecta)
await viewModel.boot(project).onSuccess((_) {
  context.useContextSomehow(); // CRASH se widget desmontado
});
```

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard
> (`mounted` / `context.mounted`) antes de tocar em `context`.

## Não deve fazer

1. **Duplicar regras de domínio** — sem validações de negócio aqui; delegue.
2. **Instanciar ViewModels diretamente** — sempre via `context.watch/read/select`.
3. **Instanciar serviços diretamente** — sem `Process.start` ou leitura de arquivo
   na `ui/`; isso é `data/`, exposto via use cases.
4. **Misturar responsabilidades** — sem lógica de processo/IO dentro de widgets.
5. **Consumir `RpcEvent` cru como `Map`** — o evento já chega tipado do domínio.
6. **Usar `context` em callbacks assíncronos** — ver "Regra crítica" acima.

## Estrutura de pastas por feature

```
feature/
├── states/              # sealed classes do estado da feature
│   └── feature_state.dart
├── viewmodels/          # ViewModels que orquestram o estado
│   └── feature_viewmodel.dart
├── widgets/             # widgets locais componentizados
│   ├── widgets.dart     # barrel
│   └── feature_widget.dart
└── feature_page.dart    # página principal (Entry Widget)
```

`core/` guarda o que é transversal a todas as features: `core/themes/` (tema dark,
`context.colors`/`context.typo`) e `core/viewmodel/` (a base `ViewModel<T>`).

## Vocabulário

- **Feature Page** — ponto de entrada da experiência da funcionalidade.
- **ViewModel** — guardião do estado e dos comandos de UI (`ChangeNotifier`).
- **State** — modelagem do que a tela pode mostrar (sealed class: `Idle`,
  `Booting`, `Streaming`, `Crashed`).
- **Consumer / Selector** — listener que reconstrói a UI a cada mudança do ViewModel.
- **Widgets Barrel** — `widgets.dart` que expõe componentes locais da feature.
