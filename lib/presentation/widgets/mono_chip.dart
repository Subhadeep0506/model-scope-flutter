import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'mono_label.dart';

class MonoChip extends StatelessWidget {
  const MonoChip(this.text, {super.key, this.color, this.background});

  final String text;

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
