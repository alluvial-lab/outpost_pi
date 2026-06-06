import 'package:flutter/foundation.dart';

/// Base de todos os ViewModels do Cockpit.
///
/// Guarda um único [state] imutável de tipo [T] e só notifica quando [emit]
/// recebe um valor diferente do atual (por `==`). Combine com sealed classes em
/// `ui/<feature>/states/` para modelar cada estado de tela explicitamente.
///
/// Páginas nunca instanciam um ViewModel: registre em `config/dependencies.dart`
/// (`addViewModel<T>(T.new)`) e injete na rota com `ViewmodelProvider<T>()`.
abstract class ViewModel<T extends Object> extends ChangeNotifier {
  ViewModel(this._state);

  T _state;
  T get state => _state;

  void emit(T newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }
}
