import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Block startup until the operator retries storage or explicitly discards
/// unreadable local transcript ciphertext.
class TranscriptStorageRecoveryPage extends StatefulWidget {
  const TranscriptStorageRecoveryPage({
    super.key,
    required this.onRetry,
    required this.onDiscard,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onDiscard;

  @override
  State<TranscriptStorageRecoveryPage> createState() =>
      _TranscriptStorageRecoveryPageState();
}

class _TranscriptStorageRecoveryPageState
    extends State<TranscriptStorageRecoveryPage> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRetry();
      if (!mounted) return;
      setState(() => _busy = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Storage is still unavailable. Try again later.';
      });
    }
  }

  Future<void> _confirmDiscard() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surface,
        title: Text(
          'Discard local transcripts?',
          style: TextStyle(color: dialogContext.colors.text),
        ),
        content: Text(
          'This permanently deletes encrypted transcripts stored on this '
          'device. Pairings and your Owner identity are kept when available.',
          style: TextStyle(color: dialogContext.colors.muted2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: dialogContext.colors.muted2),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Discard and continue',
              style: TextStyle(color: dialogContext.colors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDiscard();
      if (!mounted) return;
      setState(() => _busy = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not discard local transcripts. Nothing else was reset.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const Key('storage-recovery-scroll-view'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: ResponsiveCenter(
                maxWidth: 460,
                child: Padding(
                  key: const Key('storage-recovery-responsive-content'),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_outline, size: 40, color: colors.error),
                      const SizedBox(height: 18),
                      Text(
                        'Local transcripts unavailable',
                        textAlign: TextAlign.center,
                        style: context.typo.mono.copyWith(
                          color: colors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The local encryption key is unavailable. Outpost-Pi will '
                        'not open this ciphertext without it.',
                        textAlign: TextAlign.center,
                        style: context.typo.sansBody.copyWith(
                          color: colors.muted2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Discarding permanently removes transcripts stored on this '
                        'device. After reconnect, some current Pi-session history '
                        'may sync again, but older or local-only history may not '
                        'return. Pairing is needed only if its separate credentials '
                        'were also lost.',
                        textAlign: TextAlign.center,
                        style: context.typo.monoSmall.copyWith(
                          color: colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: context.typo.monoSmall.copyWith(
                            color: colors.error,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: _busy ? null : _retry,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Retry'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _confirmDiscard,
                        child: Text(
                          'Discard local transcripts',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
