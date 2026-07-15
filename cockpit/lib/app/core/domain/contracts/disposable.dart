/// Owns a resource that requires explicit release, such as a process or stream.
abstract class Disposable {
  /// Release resources owned by this instance at the end of its lifecycle.
  void dispose();
}
