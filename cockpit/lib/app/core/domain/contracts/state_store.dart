/// Persist small named key/value state without exposing a concrete backend.
///
/// Values must be JSON-compatible: null, booleans, finite numbers, strings,
/// lists, and maps with string keys. Mutations update the in-memory view before
/// their returned future completes; that future reports the corresponding
/// persistence attempt.
abstract interface class StateStore {
  /// Return the value stored under [key], or `null` when it is absent.
  Object? get(String key);

  /// Return the keys in the current in-memory snapshot.
  Iterable<String> get keys;

  /// Return the values in the current in-memory snapshot.
  Iterable<Object?> get values;

  /// Store [value] under [key] and report its persistence attempt.
  Future<void> put(String key, Object? value);

  /// Store [entries] as one coalescible mutation batch.
  Future<void> putAll(Map<String, Object?> entries);

  /// Remove [key] and report its persistence attempt.
  Future<void> delete(String key);

  /// Drain pending mutations to durable storage.
  Future<void> flush();
}

/// Open and lifecycle-own named [StateStore] instances.
abstract interface class StateStoreFactory {
  /// Open [name], reusing the same live instance within this factory.
  Future<StateStore> open(String name);

  /// Drain every store opened by this factory.
  Future<void> flushAll();
}
