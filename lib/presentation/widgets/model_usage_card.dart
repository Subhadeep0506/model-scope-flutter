import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/relative_time.dart';
import 'icon_tile.dart';
import 'mono_chip.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One row of the Models used list: what a model is, how much work it has done
/// and which quant answered. Models that have never answered appear at zero —
/// an unused model on disk is a gigabyte the user may want back. A model that
/// has been deleted keeps its row too, greyed and labelled: the replies it
/// produced are still part of what this device has done.
class ModelUsageCard extends StatelessWidget {
  const ModelUsageCard({super.key, required this.usage, required this.now});

  final ModelUsage usage;

  /// Passed in rather than read from the clock, so the row is a pure function
  /// of its inputs and a test can pin the "4h ago".
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

  /// `148 runs · 310ms · 4h ago`, or `0 runs · never used`.
  String get _summary {
    final last = usage.lastUsedAt;
    if (usage.runs == 0 || last == null) return '0 runs · never used';
    return '${usage.runs} run${usage.runs == 1 ? '' : 's'} · '
        '${usage.averageLatencyMs}ms · ${formatAgo(last, now)}';
  }
}
