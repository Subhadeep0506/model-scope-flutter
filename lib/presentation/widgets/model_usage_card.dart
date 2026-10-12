import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/relative_time.dart';
import 'icon_tile.dart';
import 'mono_chip.dart';
import 'mono_label.dart';
import 'section_card.dart';

class ModelUsageCard extends StatelessWidget {
  const ModelUsageCard({super.key, required this.usage, required this.now});

  final ModelUsage usage;

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
          IconTile(
            icon: usage.isInstalled
                ? Icons.memory_rounded
                : Icons.history_rounded,
            size: 34,
            iconSize: 17,
          ),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  usage.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: usage.isInstalled ? null : context.palette.muted,
                  ),
                ),
                const SizedBox(height: 3),
                MonoLabel(_summary, maxLines: 1),
              ],
            ),
          ),
          SizedBox(width: metrics.gapSm),
          MonoChip(usage.isInstalled ? usage.quantization : 'REMOVED'),
        ],
      ),
    );
  }

  String get _summary {
    final last = usage.lastUsedAt;
    if (usage.runs == 0 || last == null) return '0 runs · never used';
    return '${usage.runs} run${usage.runs == 1 ? '' : 's'} · '
        '${usage.averageLatencyMs}ms · ${formatAgo(last, now)}';
  }
}
