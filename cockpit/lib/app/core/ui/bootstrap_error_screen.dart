import 'package:flutter/material.dart';

/// Render the startup failure when persistence or module construction cannot
/// complete. This boundary is intentionally independent of the normal app
/// theme, because settings may be the resource that failed to open.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: BootstrapErrorScreen(error: error),
  );
}

/// Explain a bootstrap failure without leaving the user at a blank window.
class BootstrapErrorScreen extends StatelessWidget {
  const BootstrapErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cockpit could not start',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'The local workspace database could not be opened. '
                'Close any other Cockpit instance and try again.',
              ),
              const SizedBox(height: 16),
              SelectableText(error.toString()),
            ],
          ),
        ),
      ),
    ),
  );
}
