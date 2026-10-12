import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

class AgentRunButton extends StatelessWidget {
  const AgentRunButton({
    super.key,
    required this.isRunning,
    required this.usesDefaults,
    required this.enabled,
    required this.onRun,
    required this.onStop,
    this.isIndexing = false,
  });

  final bool isRunning;
  final bool usesDefaults;
  final bool isIndexing;
  final bool enabled;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final label = isIndexing
        ? 'Indexing the document…'
        : isRunning
        ? 'Stop'
        : (usesDefaults ? 'Run with defaults' : 'Run configured');

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isIndexing
            ? null
            : (isRunning ? onStop : (enabled ? onRun : null)),
        icon: isIndexing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 20,
              ),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.primaryIdle,
          disabledForegroundColor: palette.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: metrics.controlShape),
          textStyle: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}
