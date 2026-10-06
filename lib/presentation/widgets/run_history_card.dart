import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/relative_time.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One row under `RUN HISTORY`: what the run said, what ran it, and when.
///
/// Tapping opens the saved trace and output, which is how two models are
/// compared on the same agent after the fact.
class RunHistoryCard extends StatelessWidget {
  const RunHistoryCard({
    super.key,
    required this.run,
    required this.now,
    required this.onOpen,
  });

  final AgentRun run;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final theme = Theme.of(context);

    return SectionCard(
      onTap: onOpen,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapLg,
        vertical: metrics.gapMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  run.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: run.succeeded ? palette.ink : palette.danger,
                  ),
                ),
                const SizedBox(height: 3),
                MonoLabel(run.statsLabel, maxLines: 1),
              ],
            ),
          ),
          SizedBox(width: metrics.gapMd),
          MonoLabel(formatAgo(run.startedAt, now), maxLines: 1),
        ],
      ),
    );
  }
}
