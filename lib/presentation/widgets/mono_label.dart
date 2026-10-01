import 'package:flutter/material.dart';

import '../../config/theme/app_typography.dart';

/// Which monospace role a label plays.
enum MonoStyle { overline, meta, tag, sliderLabel, sliderValue }

/// Every run of monospace metadata in the mockups: the screen overlines, the
/// session timestamps, `Q8_0`, `T 0.70`, the metrics row and the slider
/// labels and values.
class MonoLabel extends StatelessWidget {
  const MonoLabel(
    this.text, {
    super.key,
    this.variant = MonoStyle.meta,
    this.color,
    this.maxLines,
  });

  final String text;
  final MonoStyle variant;

  /// Overrides the colour the variant would otherwise use.
  final Color? color;

  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final mono = context.mono;
    final style = switch (variant) {
      MonoStyle.overline => mono.overline,
      MonoStyle.meta => mono.meta,
      MonoStyle.tag => mono.tag,
      MonoStyle.sliderLabel => mono.sliderLabel,
      MonoStyle.sliderValue => mono.sliderValue,
    };

    return Text(
      text,
      style: color == null ? style : style.copyWith(color: color),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
