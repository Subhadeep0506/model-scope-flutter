import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One figure on the Home dashboard: a mono label, a large value and a line
/// saying what the value counts.
///
/// Sized by the grid rather than by its own content, so a tile with a long
/// caption is exactly as tall as one without — see `AppMetrics.statTile`.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.unit,
    this.accent = false,
  });

  /// `TOKENS GENERATED`, drawn in mono caps.
  final String label;

  /// The figure itself: `184.5k`, `416ms`.
  final String value;

  /// `time to first token`.
  final String caption;

  /// A mono suffix set beside the value, as `94.2 tok/s` is drawn.
  final String? unit;

  /// Draws the value in the brand green. The mockup accents one tile per
  /// screenful so the grid has a focal point rather than six equal weights.
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
