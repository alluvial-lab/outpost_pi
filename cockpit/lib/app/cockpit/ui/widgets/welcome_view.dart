import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Invite the user to create a workspace when none exists.
///
/// This view does not require pi installation because Cockpit can still act as
/// a terminal multiplexer; agent readiness is checked inside an agent tab.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.onCreateWorkspace});

  /// Starts the folder selection, configuration, and workspace creation flow.
  final Future<void> Function() onCreateWorkspace;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/branding/cockpit_logo.png',
                  width: 64,
                  height: 64,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome to Cockpit',
                style: context.typo.title.copyWith(
                  fontSize: 20,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a folder to start a workspace.',
                textAlign: TextAlign.center,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                onPressed: () => onCreateWorkspace(),
                leading: const Icon(Icons.add, size: 16),
                child: const Text('Create workspace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
