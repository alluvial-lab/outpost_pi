import 'package:app/domain/entities/update_info.dart';

/// Fetch the release manifest (`latest.json`).
///
/// This domain contract is implemented by HTTP in `data/update/`. Failures
/// such as no network, 404, invalid JSON, or an invalid schema return `null`
/// rather than throwing.
abstract class UpdateChecker {
  /// Return the latest valid release, if one can be fetched.
  Future<UpdateInfo?> fetchLatest();
}
