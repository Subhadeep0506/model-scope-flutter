import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'mono_label.dart';
import 'section_card.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.unit,
    this.accent = false,
  });

  final String label;

  final String value;

  final String caption;

  final String? unit;

  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final suffix = unit;

    return SectionCard(
      padding: EdgeInsets.all(context.metrics.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          MonoLabel(label, variant: MonoStyle.overline, maxLines: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: accent ? palette.primary : palette.ink,
                  ),
                ),
              ),
              if (suffix != null) ...<Widget>[
                const SizedBox(width: 4),
                MonoLabel(suffix, maxLines: 1),
              ],
            ],
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
