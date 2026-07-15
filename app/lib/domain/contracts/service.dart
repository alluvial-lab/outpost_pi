import 'package:app/domain/contracts/disposable.dart';

/// Mark a domain service whose composition owner must tear it down.
abstract class Service implements Disposable {
  @override
  void dispose() {}
}
