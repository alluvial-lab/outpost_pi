/// Represent an environment or permission check on the onboarding screen.
enum CheckStatus {
  /// The check is in progress.
  checking,

  /// The prerequisite is satisfied.
  ok,

  /// Installation or permission is still required.
  missing,

  /// The prerequisite does not apply on this OS and counts as satisfied.
  notApplicable,
}

/// Project a setup check into the onboarding gate decision.
extension CheckStatusX on CheckStatus {
  /// Whether this status permits workspace creation.
  ///
  /// [CheckStatus.notApplicable] counts as satisfied because the prerequisite
  /// cannot block a platform where it does not apply.
  bool get satisfied =>
      this == CheckStatus.ok || this == CheckStatus.notApplicable;
}
