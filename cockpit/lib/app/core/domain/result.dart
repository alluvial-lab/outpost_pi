/// Represent the typed outcome of an operation that can fail.
///
/// Sealing forces consumers to handle both [Success] and [Failure], avoiding
/// ambiguous `null` values and generic `catch` paths at domain boundaries.
sealed class Result<S, F> {
  const Result();

  /// Fold both branches into a common value.
  T fold<T>(T Function(S value) onSuccess, T Function(F error) onFailure);

  bool get isSuccess => this is Success<S, F>;
  bool get isFailure => this is Failure<S, F>;

  /// Transform the success value while preserving any failure.
  Result<T, F> map<T>(T Function(S value) transform) =>
      fold((s) => Success(transform(s)), (f) => Failure(f));
}

/// Represent the successful [Result] branch.
///
/// [Result.fold] dispatches this branch to its success callback, while
/// [Result.map] transforms the value.
final class Success<S, F> extends Result<S, F> {
  const Success(this.value);
  final S value;

  @override
  T fold<T>(T Function(S value) onSuccess, T Function(F error) onFailure) =>
      onSuccess(value);
}

/// Represent the failed [Result] branch.
///
/// [Result.fold] dispatches this branch to its failure callback, while
/// [Result.map] preserves the error unchanged.
final class Failure<S, F> extends Result<S, F> {
  const Failure(this.error);
  final F error;

  @override
  T fold<T>(T Function(S value) onSuccess, T Function(F error) onFailure) =>
      onFailure(error);
}
