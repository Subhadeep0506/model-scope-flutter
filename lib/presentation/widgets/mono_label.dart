import 'package:flutter/material.dart';

import '../../config/theme/app_typography.dart';

enum MonoStyle { overline, meta, tag, sliderLabel, sliderValue }

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
