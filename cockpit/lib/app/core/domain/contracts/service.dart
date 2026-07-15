import 'package:cockpit/app/core/domain/contracts/disposable.dart';

/// Mark an infrastructure service whose resources follow the injector lifecycle.
///
/// The injector chains [dispose] during teardown; process-backed services use
/// that boundary to stop child processes rather than leave orphans.
abstract class Service implements Disposable {
  @override
  void dispose() {}
}
