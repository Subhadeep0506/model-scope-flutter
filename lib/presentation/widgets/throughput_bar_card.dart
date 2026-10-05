import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';
import '../../data/models/home_stats.dart';
import 'chart_card.dart';

/// Mean tokens per second for each parameter size the device has run — how
/// far up the parameter count this phone goes before generation drags.
class ThroughputBarCard extends StatelessWidget {
  const ThroughputBarCard({super.key, required this.bars});

  final List<SizeThroughput> bars;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ceiling = _ceiling();

    return ChartCard(
      isEmpty: bars.isEmpty,
      emptyMessage: 'No replies recorded yet.',
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: ceiling,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ceiling / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: palette.outline, strokeWidth: 1),
          ),
          titlesData: _titles(context),
          barGroups: <BarChartGroupData>[
            for (var i = 0; i < bars.length; i++) _group(palette, i),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _group(AppPalette palette, int index) => BarChartGroupData(
    x: index,
    barRods: <BarChartRodData>[
      BarChartRodData(
        toY: bars[index].tokensPerSecond,
        color: palette.primary,
        width: 26,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    ],
  );

  FlTitlesData _titles(BuildContext context) {
    final style = context.mono.tag;

    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          getTitlesWidget: (value, meta) => value == meta.max
              ? const SizedBox.shrink()
              : Text(value.round().toString(), style: style),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: 1,
          getTitlesWidget: (value, _) =>
              Text(_labelAt(value.round()), style: style),
        ),
      ),
    );
  }

  String _labelAt(int index) {
    if (index < 0 || index >= bars.length) return '';
    return bars[index].paramLabel;
  }

  /// Rounds up to the next 25 tok/s, so the grid lines read as round numbers.
  double _ceiling() {
    if (bars.isEmpty) return 100;
    final highest = bars.map((bar) => bar.tokensPerSecond).reduce(math.max);
    return math.max((highest / 25).ceil() * 25, 25).toDouble();
  }
}
