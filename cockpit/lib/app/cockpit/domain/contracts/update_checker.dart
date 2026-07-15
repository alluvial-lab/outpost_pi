import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';

/// Fetch the release manifest (`latest.json`).
///
/// This domain contract has an HTTP implementation in `data/`. It is
/// **best-effort**: any failure, including no network, 404, invalid JSON, or an
/// invalid schema, returns `null` and never throws.
abstract class UpdateChecker {
  Future<UpdateInfo?> fetchLatest();
}
