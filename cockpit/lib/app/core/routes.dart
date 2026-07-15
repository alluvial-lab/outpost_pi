/// Centralize navigation paths without centralizing feature route ownership.
///
/// Each feature declares its route in its own `createModule`; these constants
/// only prevent magic strings at navigation call sites.
abstract final class RoutePaths {
  static const String shell = '/';
  static const String settings = '/settings';
}
