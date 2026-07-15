import 'package:app/domain/contracts/disposable.dart';

/// Mark a domain repository whose composition owner must tear it down.
abstract class Repository implements Disposable {
  @override
  void dispose() {}
}
