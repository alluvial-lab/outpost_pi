import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';

/// Owns the 3-step onboarding flow. Pure state machine — the actual
/// pairing happens via [PairingViewModel] surfaced inside `pair_step.dart`.
/// Once pairing succeeds (callback into [completePairing]) the flag in
/// [Preferences] flips and the router redirects to `/home`.
class OnboardingViewModel extends ViewModel<OnboardingState> {
  final Preferences _prefs;

  OnboardingViewModel(this._prefs) : super(const OnboardingInProgress());

  // ---------------------------------------------------------------------------
  // Step navigation
  // ---------------------------------------------------------------------------

  Future<void> next() async {
    final s = state;
    if (s is! OnboardingInProgress) return;
    switch (s.step) {
      case OnboardingStep.welcome:
        emit(s.copyWith(step: OnboardingStep.relay));
      case OnboardingStep.relay:
        final url = s.customRelayUrl.trim();
        final reason = relayUrlValidationMessage(url);
        if (reason != null) {
          emit(s.copyWith(customRelayError: reason));
          return;
        }
        // The pair step must never observe an unconfigured relay.
        await _prefs.setRelayUrl(url);
        emit(s.copyWith(step: OnboardingStep.pair, clearCustomError: true));
      case OnboardingStep.pair:
      // Advancing from pair happens via `completePairing` (callback
      // when pair_ok lands). Manual `next()` from pair is a no-op.
    }
  }

  void back() {
    final s = state;
    if (s is! OnboardingInProgress) return;
    switch (s.step) {
      case OnboardingStep.welcome:
        return; // first step — no back
      case OnboardingStep.relay:
        emit(s.copyWith(step: OnboardingStep.welcome));
      case OnboardingStep.pair:
        emit(s.copyWith(step: OnboardingStep.relay));
    }
  }

  // ---------------------------------------------------------------------------
  // Step 2 — relay configuration
  // ---------------------------------------------------------------------------

  /// Updates the in-flight self-hosted URL string. Validates on-the-fly:
  /// inline error if non-empty + invalid. Empty input clears the error while
  /// the user is typing; submitting it renders the shared validation error.
  void setCustomRelayUrl(String url) {
    final s = state;
    if (s is! OnboardingInProgress) return;
    final error = url.isEmpty ? null : relayUrlValidationMessage(url);
    emit(
      s.copyWith(
        customRelayUrl: url,
        customRelayError: error,
        clearCustomError: error == null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 — pairing success
  // ---------------------------------------------------------------------------

  /// Called by `pair_step.dart` when the underlying PairingViewModel
  /// reports a successful pair_ok. Flips the onboarding flag in
  /// preferences and transitions to [OnboardingComplete] — the
  /// OnboardingPage observes that and navigates to `/home`.
  Future<void> completePairing() async {
    await _prefs.setOnboardingCompleted(true);
    emit(const OnboardingComplete());
  }

  /// User dismisses the QR step ("Scan later"). Onboarding is marked
  /// done so we don't loop back here, but no peer is paired — Home
  /// will show the "Awaiting pairing" empty state until the user pairs
  /// from there.
  Future<void> skipPairing() async {
    await _prefs.setOnboardingCompleted(true);
    emit(const OnboardingComplete());
  }
}
