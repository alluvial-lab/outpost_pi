import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:flutter/material.dart';

/// Onboarding step 2 — require the URL of the user's self-hosted relay.
///
/// The relay URL remains in [OnboardingInProgress] so validation errors from
/// the ViewModel render here. This widget owns its controller for its mounted
/// lifetime instead of allocating one during every rebuild.
class RelayStep extends StatefulWidget {
  final OnboardingInProgress state;
  final ValueChanged<String> onCustomUrl;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const RelayStep({
    super.key,
    required this.state,
    required this.onCustomUrl,
    required this.onBack,
    required this.onNext,
  });

  @override
  State<RelayStep> createState() => _RelayStepState();
}

class _RelayStepState extends State<RelayStep> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.customRelayUrl);
  }

  @override
  void didUpdateWidget(covariant RelayStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrl = widget.state.customRelayUrl;
    if (_controller.text == nextUrl) return;
    _controller.value = TextEditingValue(
      text: nextUrl,
      selection: TextSelection.collapsed(offset: nextUrl.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            'Configure your relay',
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 16,
              color: colors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the URL for the self-hosted relay you operate.',
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 11,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: widget.onCustomUrl,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 12,
              color: colors.text,
            ),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Self-hosted relay URL',
              hintText: 'https://my-relay.example.com',
              hintStyle: TextStyle(
                fontFamily: kMonoFamily,
                color: colors.muted,
              ),
              errorText: widget.state.customRelayError,
              errorStyle: TextStyle(
                fontFamily: kMonoFamily,
                fontSize: 10,
                color: colors.error,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              OutlinedButton(
                onPressed: widget.onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.muted,
                  side: BorderSide(color: colors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(fontFamily: kMonoFamily, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  // Validation belongs to the ViewModel so an empty submit can
                  // surface the shared relay URL validation message.
                  onPressed: widget.onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
