/// An opaque JSON object preserved at the RPC-to-domain boundary.
///
/// The object intentionally does not validate tool-specific fields. RPC payload
/// shapes are owned by Pi and may evolve independently of Cockpit.
final class RpcJsonObject {
  RpcJsonObject._(Map<String, Object?> values)
    : values = Map<String, Object?>.unmodifiable(values);

  /// The fallback object used when an RPC field is not an object.
  static final empty = RpcJsonObject._(const <String, Object?>{});

  /// Convert a wire value to an object, coercing wire keys to strings.
  ///
  /// Returns `null` for absent or non-object values. Nested values are kept as
  /// decoded; this type only owns the top-level object boundary.
  static RpcJsonObject? tryFromWire(Object? value) {
    if (value is! Map) return null;
    return RpcJsonObject._(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  /// The shallowly immutable top-level values of this JSON object.
  final Map<String, Object?> values;
}
