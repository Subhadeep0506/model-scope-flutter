import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'mono_label.dart';

/// The small outlined monospace tag the mockups repeat for `Q4_K_M`, `1.29 GB`,
/// `1.5B` and the `Model` / `MMProj` / `Adapter` badges.
class MonoChip extends StatelessWidget {
  const MonoChip(this.text, {super.key, this.color, this.background});

  final String text;

  /// Overrides the text colour, for a badge that needs to stand out.
  final Color? color;

  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapSm,
        vertical: metrics.gapXs + 1,
      ),
      decoration: BoxDecoration(
        color: background ?? palette.surface,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
        border: Border.all(color: palette.outline),
      ),
      child: MonoLabel(text, variant: MonoStyle.tag, color: color),
    );
  }
}
