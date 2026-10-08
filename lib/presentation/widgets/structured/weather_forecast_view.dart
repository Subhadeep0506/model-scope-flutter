import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../config/theme/app_typography.dart';
import '../../../data/models/json_read.dart';
import '../chart_card.dart';
import '../mono_label.dart';
import 'data_table_card.dart';
import 'headline_chips.dart';
import 'structured_view.dart';

/// Weather Report's answer: conditions now, then the three-day trend.
///
/// The forecast arrives as a flat list of one row per place per day rather
/// than nested under each place. That is the shape a chart wants, and it is
/// also the easiest for a small model to fill — one object per row, with no
/// nesting to lose track of halfway through.
class WeatherForecastView implements StructuredView {
  const WeatherForecastView();

  @override
  Widget build(BuildContext context, Map<String, dynamic> data) {
    final metrics = context.metrics;
    final places = readObjectList(data['places']);
    final unit = readString(data['unit']);
    final series = _seriesOf(readObjectList(data['forecast']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HeadlineChips(
          headlines: <Headline>[
            Headline(
              label: 'Warmest',
              value: readString(data['warmest']),
              accent: true,
            ),
            Headline(label: 'Coldest', value: readString(data['coldest'])),
            Headline(label: 'Rain', value: _rain(data)),
          ],
        ),
        SizedBox(height: metrics.gapLg),
        const MonoLabel('RIGHT NOW', variant: MonoStyle.overline),
        SizedBox(height: metrics.gapSm),
        DataTableCard(
          columns: <DataField>[
            DataField(
              label: 'Place',
              flex: 3,
              cell: (row) => readString(row['place']),
            ),
            DataField(
              label: 'Temp',
              flex: 2,
              numeric: true,
              cell: (row) => _degrees(row['temperature'], unit),
            ),
            DataField(
              label: 'Conditions',
              flex: 3,
              cell: (row) => readString(row['condition']),
            ),
            DataField(
              label: 'Wind',
              flex: 2,
              cell: (row) => readString(row['wind']),
            ),
          ],
          rows: places,
          emptyMessage: 'The model reported on no places.',
        ),
        if (series.isNotEmpty) ...<Widget>[
          SizedBox(height: metrics.gapXl),
          const MonoLabel(
            'HIGHS, NEXT THREE DAYS',
            variant: MonoStyle.overline,
          ),
          SizedBox(height: metrics.gapSm),
          _ForecastChart(series: series, unit: unit),
          SizedBox(height: metrics.gapMd),
          _Legend(series: series),
        ],
      ],
    );
  }

  /// `Tokyo, Berlin`, or empty when nothing is expected — which drops the chip
  /// rather than drawing `RAIN / none`.
  static String _rain(Map<String, dynamic> data) =>
      readStringList(data['rain_expected']).join(', ');

  static String _degrees(Object? value, String unit) {
    if (value is! num) return '';
    final whole = value == value.truncateToDouble();
    final text = whole ? value.truncate().toString() : value.toStringAsFixed(1);
    return unit.isEmpty ? text : '$text$unit';
  }

  /// Groups the flat forecast rows into one line per place, keeping the days
  /// in the order they first appear so every line shares an x axis.
  static List<_Series> _seriesOf(List<Map<String, dynamic>> forecast) {
    final days = <String>[];
    final byPlace = <String, Map<String, double>>{};

    for (final row in forecast) {
      final place = readString(row['place']);
      final day = readString(row['day']);
      final high = row['max_temp'];
      if (place.isEmpty || day.isEmpty || high is! num) continue;

      if (!days.contains(day)) days.add(day);
      byPlace.putIfAbsent(place, () => <String, double>{})[day] = high
          .toDouble();
    }

    return <_Series>[
      for (final entry in byPlace.entries)
        _Series(
          place: entry.key,
          // Indexed against the shared day list, so a place missing a day
          // leaves a gap in its line rather than shifting it left.
          spots: <FlSpot>[
            for (final (index, day) in days.indexed)
              if (entry.value[day] case final high?)
                FlSpot(index.toDouble(), high),
          ],
          days: days,
        ),
    ];
  }
}

class _Series {
  const _Series({required this.place, required this.spots, required this.days});

  final String place;
  final List<FlSpot> spots;
  final List<String> days;
}

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.series, required this.unit});

  final List<_Series> series;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = series.first.days;
    final (min, max) = _bounds();

    return ChartCard(
      isEmpty: false,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(days.length - 1, 1).toDouble(),
          minY: min,
          maxY: max,
          lineTouchData: const LineTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max((max - min) / 4, 1),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: palette.outline, strokeWidth: 1),
          ),
          titlesData: _titles(context, days),
          lineBarsData: <LineChartBarData>[
            for (final (index, line) in series.indexed)
              LineChartBarData(
                spots: line.spots,
                isCurved: true,
                curveSmoothness: 0.25,
                preventCurveOverShooting: true,
                color: palette.seriesAt(index),
                barWidth: 2.5,
                // No fill under the lines: with five of them overlapping, the
                // shading hides whichever line is drawn underneath.
                belowBarData: BarAreaData(show: false),
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 3,
                    color: palette.seriesAt(index),
                    strokeWidth: 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Padded by a degree either side, so a line does not sit on the axis.
  (double, double) _bounds() {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (final line in series) {
      for (final spot in line.spots) {
        low = math.min(low, spot.y);
        high = math.max(high, spot.y);
      }
    }
    if (!low.isFinite || !high.isFinite) return (0, 1);
    if (low == high) return (low - 1, high + 1);
    return (low - 1, high + 1);
  }

  FlTitlesData _titles(BuildContext context, List<String> days) {
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
              : Text('${value.round()}$unit', style: style),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: 1,
          getTitlesWidget: (value, _) {
            final index = value.round();
            if (index < 0 || index >= days.length) {
              return const SizedBox.shrink();
            }
            return Text(_shorten(days[index]), style: style);
          },
        ),
      ),
    );
  }

  /// `2026-10-09` → `10-09`. The model writes the day however it likes, and a
  /// full ISO date will not fit three to a phone's width.
  static String _shorten(String day) =>
      day.length > 5 && day[4] == '-' ? day.substring(5) : day;
}

/// Which colour is which place. Without it the chart is five unnamed lines.
class _Legend extends StatelessWidget {
  const _Legend({required this.series});

  final List<_Series> series;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Wrap(
      spacing: metrics.gapLg,
      runSpacing: metrics.gapSm,
      children: <Widget>[
        for (final (index, line) in series.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 12,
                height: 3,
                decoration: BoxDecoration(
                  color: palette.seriesAt(index),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Text(line.place, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
