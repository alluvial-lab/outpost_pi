import 'package:app/domain/contracts/contracts.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:auto_injector/auto_injector.dart';

/// Wrap [AutoInjector] with layer-aware registrations and disposal ownership.
///
/// Typed registration methods make each binding's architectural role explicit.
/// Services and repositories are injector-owned lazy singletons; ViewModels and
/// use cases are constructed on demand. Use [addInstance] for ready SDK values
/// and [addOther] for infrastructure that has no domain lifecycle contract.
class CustomInjector {
  final _injector = AutoInjector();

  /// Resolve a registered dependency.
  ///
  /// ViewModel bindings create a new instance for each lookup rather than
  /// retaining route state in the injector.
  T get<T extends Object>() => _injector.get<T>();

  /// Register an already-constructed instance for the app lifetime.
  ///
  /// An optional [onDispose] binds cleanup to this injector's application
  /// lifetime, rather than leaving the instance's resource ownership to a
  /// widget or ad-hoc global teardown list.
  void addInstance<T>(T instance, {void Function(T value)? onDispose}) {
    _injector.addInstance<T>(
      instance,
      config: onDispose == null ? null : BindConfig<T>(onDispose: onDispose),
    );
  }

  /// Register a lazy singleton without imposing a domain disposal contract.
  void addOther<T>(Function constructor) {
    _injector.addLazySingleton<T>(constructor);
  }

  /// Register an injector-owned lazy service and dispose it at shutdown.
  void addService<T extends Service>(Function constructor) {
    _injector.addLazySingleton<T>(
      constructor,
      config: BindConfig(onDispose: (value) => value.dispose()),
    );
  }

  /// Register an injector-owned lazy repository and dispose it at shutdown.
  void addRepository<T extends Repository>(Function constructor) {
    _injector.addLazySingleton<T>(
      constructor,
      config: BindConfig(onDispose: (value) => value.dispose()),
    );
  }

  /// Register a ViewModel factory so state cannot leak across route mounts.
  void addViewModel<T extends ViewModel>(Function constructor) {
    _injector.add(constructor);
  }

  /// Register a use-case factory for demand-time resolution.
  void addUseCase<T extends UseCase>(Function constructor) {
    _injector.add(constructor);
  }

  /// Dispose injector-owned bindings and reset the registry.
  void dispose() => _injector.dispose();

  /// Seal registration after bootstrap so the dependency graph cannot drift.
  void commit() => _injector.commit();
}
