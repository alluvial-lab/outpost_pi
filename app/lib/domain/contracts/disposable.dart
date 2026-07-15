/// Define explicit lifecycle ownership for resources held by an object.
abstract class Disposable {
  /// Release every resource owned by this instance exactly once at teardown.
  void dispose();
}
