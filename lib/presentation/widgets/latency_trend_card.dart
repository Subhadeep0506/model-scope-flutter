import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/theme/app_palette.dart';
import '../../config/theme/app_typography.dart';
import '../../data/models/home_stats.dart';
import 'chart_card.dart';

/// Time to first token over the last seven days. Days with no replies are left
/// out rather than plotted as zero, which would claim the model answered
/// instantly on a day nobody chatted.
class LatencyTrendCard extends StatelessWidget {
  const LatencyTrendCard({super.key, required this.trend});

  /// Matches the mockup's `Mon Tue Wed …` axis.
  static final DateFormat _weekday = DateFormat('E');

  final List<DailyLatency> trend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final spots = <FlSpot>[
      for (var i = 0; i < trend.length; i++)
        if (trend[i].averageLatencyMs case final latency?)
          FlSpot(i.toDouble(), latency.toDouble()),
    ];

    return ChartCard(
      isEmpty: spots.isEmpty,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(trend.length - 1, 1).toDouble(),
          minY: 0,
          maxY: _ceiling(spots),
          lineTouchData: const LineTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _ceiling(spots) / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: palette.outline, strokeWidth: 1),
          ),
          titlesData: _titles(context),
          lineBarsData: <LineChartBarData>[_line(palette, spots)],
        ),
      ),
    );
  }

  LineChartBarData _line(AppPalette palette, List<FlSpot> spots) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.25,
        preventCurveOverShooting: true,
        color: palette.primary,
        barWidth: 2.5,
        // A single reading has no line to draw, so it shows as a point.
        dotData: FlDotData(show: spots.length == 1),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              palette.primary.withValues(alpha: 0.22),
              palette.primary.withValues(alpha: 0.02),
            ],
          ),
        ),
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
    if (index < 0 || index >= trend.length) return '';
    return _weekday.format(trend[index].day);
  }

  /// Rounds the axis up to the next 150ms so the grid lines land on round
  /// numbers rather than on whatever the maximum happened to be.
  static double _ceiling(List<FlSpot> spots) {
    if (spots.isEmpty) return 600;
    final highest = spots.map((spot) => spot.y).reduce(math.max);
    return math.max((highest / 150).ceil() * 150, 150).toDouble();
  }
}
