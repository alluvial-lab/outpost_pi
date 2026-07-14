// Sealed state for OnboardingViewModel. Switch exhaustively in
// OnboardingPage.build().

enum OnboardingStep { welcome, relay, pair }

sealed class OnboardingState {
  const OnboardingState();
}

class OnboardingInProgress extends OnboardingState {
  final OnboardingStep step;
  final String customRelayUrl;
  final String? customRelayError;

  const OnboardingInProgress({
    this.step = OnboardingStep.welcome,
    this.customRelayUrl = '',
    this.customRelayError,
  });

  OnboardingInProgress copyWith({
    OnboardingStep? step,
    String? customRelayUrl,
    String? customRelayError,
    bool clearCustomError = false,
  }) => OnboardingInProgress(
    step: step ?? this.step,
    customRelayUrl: customRelayUrl ?? this.customRelayUrl,
    customRelayError: clearCustomError
        ? null
        : (customRelayError ?? this.customRelayError),
  );

  @override
  bool operator ==(Object other) =>
      other is OnboardingInProgress &&
      other.step == step &&
      other.customRelayUrl == customRelayUrl &&
      other.customRelayError == customRelayError;

  @override
  int get hashCode => Object.hash(step, customRelayUrl, customRelayError);
}

class OnboardingComplete extends OnboardingState {
  const OnboardingComplete();
}
