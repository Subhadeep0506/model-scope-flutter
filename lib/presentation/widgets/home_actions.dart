import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The pair of buttons that close the Home screen. Both are real routes: Run
/// agent lands on the Agent tab's placeholder, which explains itself, rather
/// than being a dead button here.
class HomeActions extends StatelessWidget {
  const HomeActions({
    super.key,
    required this.onNewChat,
    required this.onRunAgent,
  });

  final VoidCallback onNewChat;
  final VoidCallback onRunAgent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        Expanded(
          child: _Action(
            icon: Icons.bolt_rounded,
            label: 'New chat',
            background: palette.primary,
            foreground: palette.onPrimary,
            onPressed: onNewChat,
          ),
        ),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: _Action(
            icon: Icons.monitor_heart_outlined,
            label: 'Run agent',
            background: palette.fieldFill,
            foreground: palette.primary,
            onPressed: onRunAgent,
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.gapMd,
          vertical: metrics.gapLg,
        ),
        shape: RoundedRectangleBorder(borderRadius: metrics.cardShape),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          SizedBox(width: metrics.gapSm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: foreground),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}
