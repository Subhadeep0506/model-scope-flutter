import 'package:checks/checks.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/presentation/widgets/structured/price_table_view.dart';
import 'package:model_scope_flutter/presentation/widgets/structured/structured_view.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  /// Draws [data] through the component [view] names, as the output card does.
  Future<void> pumpView(
    WidgetTester tester,
    String? view,
    Map<String, dynamic> data,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) =>
              SingleChildScrollView(child: viewFor(view).build(context, data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> priceData() => <String, dynamic>{
    'product': 'Sony WH-1000XM5',
    'currency': '₹',
    'offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'retailer': 'Retailer A',
        'price': 26990,
        'shipping': 'Free',
        'stock': 'In stock',
      },
      <String, dynamic>{
        'retailer': 'Retailer C',
        'price': 25750.5,
        'shipping': 'Free',
        'stock': 'In stock',
      },
    ],
    'cheapest_retailer': 'Retailer C',
    'best_for_speed': 'Retailer A',
    'price_gap': 1240,
  };

  Map<String, dynamic> weatherData() => <String, dynamic>{
    'unit': '°C',
    'places': <Map<String, dynamic>>[
      <String, dynamic>{
        'place': 'London',
        'temperature': 14,
        'condition': 'overcast',
        'humidity': 71,
        'wind': '11 km/h',
      },
      <String, dynamic>{
        'place': 'Tokyo',
        'temperature': 23,
        'condition': 'clear sky',
        'humidity': 54,
        'wind': '8 km/h',
      },
    ],
    'forecast': <Map<String, dynamic>>[
      for (final place in <String>['London', 'Tokyo'])
        for (final day in <String>['2026-10-08', '2026-10-09', '2026-10-10'])
          <String, dynamic>{
            'place': place,
            'day': day,
            'min_temp': place == 'Tokyo' ? 18 : 10,
            'max_temp': place == 'Tokyo' ? 24 : 16,
            'rain_chance': 20,
          },
    ],
    'warmest': 'Tokyo',
    'coldest': 'London',
    'rain_expected': <String>['London'],
  };

  group('price_table', () {
    testWidgets('draws a row per offer, with the figures', (tester) async {
      await pumpView(tester, 'price_table', priceData());

      check(find.text('Sony WH-1000XM5').evaluate()).isNotEmpty();
      check(find.text('Retailer A').evaluate()).isNotEmpty();
      check(find.text('Retailer C').evaluate()).isNotEmpty();
      // Grouped, and the trailing zeros dropped on a whole number.
      check(find.text('₹ 26,990').evaluate()).isNotEmpty();
      check(find.text('₹ 25,750.50').evaluate()).isNotEmpty();
    });

    testWidgets('leads with the retailer the model chose', (tester) async {
      await pumpView(tester, 'price_table', priceData());

      check(find.text('CHEAPEST').evaluate()).isNotEmpty();
      check(find.text('FASTEST').evaluate()).isNotEmpty();
      check(find.text('₹ 1,240').evaluate()).isNotEmpty();
    });

    testWidgets('a field the model left out draws a dash', (tester) async {
      final data = priceData();
      (data['offers'] as List<Map<String, dynamic>>).first.remove('shipping');

      await pumpView(tester, 'price_table', data);

      // A blank cell reads as a layout fault; a dash reads as missing data,
      // which is what it is and worth seeing.
      check(find.text('—').evaluate()).isNotEmpty();
    });

    testWidgets('a headline the model left empty is dropped', (tester) async {
      final data = priceData()..remove('best_for_speed');

      await pumpView(tester, 'price_table', data);

      check(find.text('FASTEST').evaluate()).isEmpty();
      check(find.text('CHEAPEST').evaluate()).isNotEmpty();
    });

    testWidgets('no offers says so rather than drawing an empty table', (
      tester,
    ) async {
      await pumpView(tester, 'price_table', <String, dynamic>{
        'offers': <Map<String, dynamic>>[],
      });

      check(find.textContaining('no offers').evaluate()).isNotEmpty();
    });
  });

  group('formatMoney', () {
    test('groups thousands and drops trailing zeros on a whole number', () {
      check(formatMoney(25750)).equals('25,750');
      check(formatMoney(25750.5)).equals('25,750.50');
      check(formatMoney(999)).equals('999');
      check(formatMoney(1234567.89)).equals('1,234,567.89');
      check(formatMoney(-1240)).equals('-1,240');
    });
  });

  group('weather_forecast', () {
    testWidgets('draws current conditions and one line per place', (
      tester,
    ) async {
      await pumpView(tester, 'weather_forecast', weatherData());

      check(find.text('London').evaluate()).isNotEmpty();
      check(find.text('Tokyo').evaluate()).isNotEmpty();
      check(find.text('overcast').evaluate()).isNotEmpty();
      check(find.text('23°C').evaluate()).isNotEmpty();

      // Two places, two lines, and a legend entry for each.
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      check(chart.data.lineBarsData).length.equals(2);
      check(chart.data.lineBarsData.first.spots).length.equals(3);
    });

    testWidgets('the warmest place leads', (tester) async {
      await pumpView(tester, 'weather_forecast', weatherData());

      check(find.text('WARMEST').evaluate()).isNotEmpty();
      check(find.text('COLDEST').evaluate()).isNotEmpty();
      check(find.text('RAIN').evaluate()).isNotEmpty();
    });

    testWidgets('no forecast means no chart, not an empty one', (tester) async {
      final data = weatherData()..remove('forecast');

      await pumpView(tester, 'weather_forecast', data);

      check(find.byType(LineChart).evaluate()).isEmpty();
      // The table is still drawn — losing the chart must not lose the data.
      check(find.text('London').evaluate()).isNotEmpty();
    });

    testWidgets('a place missing a day keeps its other days', (tester) async {
      final data = weatherData();
      (data['forecast'] as List<Map<String, dynamic>>).removeWhere(
        (row) => row['place'] == 'Tokyo' && row['day'] == '2026-10-09',
      );

      await pumpView(tester, 'weather_forecast', data);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final tokyo = chart.data.lineBarsData.last;
      check(tokyo.spots).length.equals(2);
      // Indexed against the shared day list, so the line keeps its place on
      // the x axis rather than shifting left into the gap.
      check(tokyo.spots.last.x).equals(2);
    });
  });

  group('the generic fallback', () {
    testWidgets('turns an unknown agent\'s array into a table', (tester) async {
      await pumpView(tester, 'something_this_build_never_heard_of', {
        'total': 2,
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Alpha', 'score': 9},
          <String, dynamic>{'name': 'Beta', 'score': 4},
        ],
      });

      check(find.text('TOTAL').evaluate()).isNotEmpty();
      check(find.text('ROWS').evaluate()).isNotEmpty();
      check(find.text('NAME').evaluate()).isNotEmpty();
      check(find.text('Alpha').evaluate()).isNotEmpty();
      check(find.text('Beta').evaluate()).isNotEmpty();
    });

    testWidgets('a list of words is a line, not a one-column table', (
      tester,
    ) async {
      await pumpView(tester, null, <String, dynamic>{
        'tags': <String>['fast', 'cheap'],
      });

      check(find.text('fast, cheap').evaluate()).isNotEmpty();
    });

    testWidgets('rows with different keys still line up', (tester) async {
      await pumpView(tester, null, <String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'a': 1},
          <String, dynamic>{'b': 2},
        ],
      });

      // The union of every row's keys, so a row missing a field sits under
      // the right heading with a dash rather than shifting columns.
      check(find.text('A').evaluate()).isNotEmpty();
      check(find.text('B').evaluate()).isNotEmpty();
      check(find.text('—').evaluate()).length.equals(2);
    });

    testWidgets('an empty result says so', (tester) async {
      await pumpView(tester, null, <String, dynamic>{});

      check(find.textContaining('empty result').evaluate()).isNotEmpty();
    });
  });

  group('isKnownView', () {
    test('names the components this build ships', () {
      check(isKnownView('price_table')).isTrue();
      check(isKnownView('weather_forecast')).isTrue();
      check(isKnownView('anything_else')).isFalse();
      check(isKnownView(null)).isFalse();
    });
  });
}
