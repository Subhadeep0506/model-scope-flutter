import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/relative_time.dart';
import 'icon_tile.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One row of the Recent activity feed. The glyph is the only thing that tells
/// the three kinds apart at a glance, so it follows [ActivityKind] rather than
/// the wording of the title.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.entry, required this.now});

  final ActivityEntry entry;

  /// Passed in so the stamp is a pure function of its inputs.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SectionCard(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapMd,
      ),
      child: Row(
        children: <Widget>[
          IconTile(icon: _glyph, size: 34, iconSize: 17),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                MonoLabel(entry.subtitle, maxLines: 1),
              ],
            ),
          ),
          SizedBox(width: metrics.gapSm),
          MonoLabel(formatAgo(entry.at, now), maxLines: 1),
        ],
      ),
    );
  }

  IconData get _glyph => switch (entry.kind) {
    ActivityKind.session => Icons.chat_bubble_outline_rounded,
    ActivityKind.install => Icons.download_rounded,
    ActivityKind.agentRun => Icons.smart_toy_outlined,
  };
}
