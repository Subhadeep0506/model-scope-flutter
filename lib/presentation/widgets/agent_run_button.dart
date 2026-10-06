import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The one green button on an agent's screen.
///
/// Its label says what pressing it will actually do: `Run with defaults` when
/// nothing has been edited, `Run configured` once something has, and `Stop`
/// while a run is going — one button rather than two, as the mockups draw it.
class AgentRunButton extends StatelessWidget {
  const AgentRunButton({
    super.key,
    required this.isRunning,
    required this.usesDefaults,
    required this.enabled,
    required this.onRun,
    required this.onStop,
  });

  final bool isRunning;
  final bool usesDefaults;

  /// False when something stops the agent running — no model, no key.
  final bool enabled;

  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final label = isRunning
        ? 'Stop'
        : (usesDefaults ? 'Run with defaults' : 'Run configured');

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isRunning ? onStop : (enabled ? onRun : null),
        icon: Icon(
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
