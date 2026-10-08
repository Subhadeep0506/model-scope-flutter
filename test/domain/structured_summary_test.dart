import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/structured_summary.dart';

void main() {
  group('decodeStructured', () {
    test('reads a JSON object', () {
      check(decodeStructured('{"a": 1}'))
          .isNotNull()
          .deepEquals(<String, Object?>{'a': 1});
    });

    test('prose is not structured', () {
      check(decodeStructured('Retailer C is cheapest at 25,750.')).isNull();
    });

    test('JSON cut off part-way is not structured', () {
      // What a constrained answer looks like when the context runs out.
      check(decodeStructured('{"offers": [{"retailer": "A"')).isNull();
    });

    test('a bare array is not an answer', () {
      // Every schema this build writes is an object at the top level.
      check(decodeStructured('[1, 2, 3]')).isNull();
    });

    test('whitespace around the object does not hide it', () {
      check(decodeStructured('\n  {"a": 1}\n ')).isNotNull();
    });
  });

  group('price_table', () {
    test('leads with the retailer the model picked', () {
      final line = summariseStructured('price_table', '''
        {"cheapest_retailer": "Retailer C",
         "offers": [{"retailer": "A"}, {"retailer": "B"}, {"retailer": "C"}]}
      ''');

      check(line).equals('Cheapest: Retailer C · 3 offers');
    });

    test('falls back to the count when the model named no winner', () {
      final line = summariseStructured(
        'price_table',
        '{"offers": [{"retailer": "A"}]}',
      );

      check(line).equals('1 offer');
    });

    test('no offers at all still reads as a sentence', () {
      check(summariseStructured('price_table', '{"offers": []}'))
          .equals('0 offers');
    });
  });

  group('weather_forecast', () {
    test('leads with the warmest place', () {
      final line = summariseStructured('weather_forecast', '''
        {"warmest": "Tokyo",
         "places": [{"place": "Tokyo"}, {"place": "Berlin"}]}
      ''');

      check(line).equals('Warmest: Tokyo · 2 places');
    });

    test('one place is not "1 places"', () {
      check(
        summariseStructured('weather_forecast', '{"places": [{"place": "A"}]}'),
      ).equals('1 place');
    });
  });

  group('an agent nobody wrote a summary for', () {
    test('names the fields it filled in', () {
      final line = summariseStructured(null, '{"total": 4, "status": "ok"}');

      check(line).equals('total, status');
    });

    test('counts the rest past three', () {
      final line = summariseStructured('something_else', '''
        {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5}
      ''');

      check(line).equals('a, b, c and 2 more');
    });

    test('an empty object has nothing to say', () {
      check(summariseStructured(null, '{}')).isNull();
    });
  });

  test('prose has no structured summary, whatever the view says', () {
    // A run whose schema was refused still carries the view name.
    check(summariseStructured('price_table', 'Retailer C is cheapest.'))
        .isNull();
  });
}
