import 'package:auto_injector/auto_injector.dart';
import 'package:cockpit/domain/contracts/contracts.dart';
import 'package:cockpit/ui/core/viewmodel/viewmodel.dart';

/// Fachada tipada sobre o [AutoInjector]. Cada método amarra um tipo à camada
/// a que pertence (`Service`, `UseCase`, `ViewModel`) — documentação viva do
/// registro e do ciclo de vida.
class CustomInjector {
  final AutoInjector _injector = AutoInjector();

  /// Resolve uma instância registrada.
  T get<T extends Object>() => _injector.get<T>();

  /// Valor já construído (singleton de fato) — ex.: `PiSpawnConfig`.
  void addInstance<T>(T instance) => _injector.addInstance<T>(instance);

  /// [Service] como singleton preguiçoso; `dispose()` encadeado no descarte.
  /// **Crítico aqui**: o dispose do gateway RPC mata o child process.
  void addService<T extends Service>(Function constructor) {
    _injector.addLazySingleton<T>(
      constructor,
      config: BindConfig(onDispose: (value) => value.dispose()),
    );
  }

  /// [UseCase] — resolvido sob demanda (nova instância por `get`).
  void addUseCase<T extends UseCase>(Function constructor) =>
      _injector.add(constructor);

  /// [ViewModel] — nova instância por tela (estado não vaza entre rotas).
  void addViewModel<T extends ViewModel>(Function constructor) =>
      _injector.add(constructor);

  /// Bloqueia novas inserções. Chamado ao fim de `setupDependencies()`.
  void commit() => _injector.commit();

  /// Libera tudo (dispara os `onDispose` → mata os child processes).
  void dispose() => _injector.dispose();
}
