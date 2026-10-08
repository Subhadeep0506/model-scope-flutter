import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../mono_label.dart';

/// One figure a structured answer leads with, e.g. `CHEAPEST / Retailer C`.
class Headline {
  const Headline({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;

  /// Drawn in the brand colour. One headline per answer should carry it —
  /// the cheapest price, the warmest city — and the rest should not, or the
  /// emphasis says nothing.
  final bool accent;
}

/// The row of figures above a structured answer's table.
///
/// This is where the judgement goes now that the agents answer in data rather
/// than prose: the model still has to decide which retailer is cheapest, it
/// just returns the name in a field instead of a sentence. A headline whose
/// field the model left empty is dropped rather than drawn blank.
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
