import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../mono_label.dart';

class Headline {
  const Headline({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;

  final bool accent;
}

class HeadlineChips extends StatelessWidget {
  const HeadlineChips({super.key, required this.headlines});

  final List<Headline> headlines;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final shown = <Headline>[
      for (final headline in headlines)
        if (headline.value.trim().isNotEmpty) headline,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: metrics.gapSm,
      runSpacing: metrics.gapSm,
      children: <Widget>[
        for (final headline in shown) _Chip(headline: headline),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.headline});

  final Headline headline;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapSm,
      ),
      decoration: BoxDecoration(
        color: headline.accent ? palette.pill : palette.fieldFill,
        borderRadius: metrics.controlShape,
        border: Border.all(
          color: headline.accent ? palette.primary : palette.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MonoLabel(headline.label.toUpperCase(), variant: MonoStyle.overline),
          const SizedBox(height: 2),
          Text(
            headline.value,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: headline.accent ? palette.primary : null),
          ),
        ],
      ),
    );
  }
}
