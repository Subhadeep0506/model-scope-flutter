import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'section_card.dart';

/// The card a Home chart is drawn inside.
///
/// Owns the one decision both charts share: what to show before anything has
/// been generated. Empty axes would read as a chart that failed to load, so a
/// plain sentence takes their place until there is something to plot.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.isEmpty,
    required this.child,
    this.emptyMessage = 'No replies recorded yet.',
  });

  final bool isEmpty;
  final Widget child;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SectionCard(
      padding: EdgeInsets.fromLTRB(
        metrics.gapSm,
        metrics.gapLg,
        metrics.gapLg,
        metrics.gapSm,
      ),
      child: SizedBox(
        height: metrics.chartPlot,
        child: isEmpty ? _Empty(message: emptyMessage) : child,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );
}
