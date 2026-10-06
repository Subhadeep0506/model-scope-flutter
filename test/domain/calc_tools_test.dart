import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/tools/calc_tools.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';

void main() {
  /// Calls [tool] the way `package:nobodywho` does — by name, through
  /// [Function.apply]. These three are synchronous, unlike the web tools, so
  /// the result comes back directly.
  String invoke(ToolDefinition tool, String expression) => Function.apply(
    tool.function,
    const <Object?>[],
    <Symbol, Object?>{#expression: expression},
  ) as String;

  group('shape', () {
    test('each takes one required named String', () {
      for (final tool in <ToolDefinition>[
        calculatorTool(),
        dateMathTool(),
        unitConvertTool(),
      ]) {
        check(
          tool.function.runtimeType.toString(),
          because: tool.name,
        ).contains('{required String expression}');
        check(
          tool.parameterDescriptions.keys.toList(),
          because: tool.name,
        ).deepEquals(<String>['expression']);
      }
    });
  });

  group('calculator', () {
    test('works out a sum and shows its working', () {
      check(invoke(calculatorTool(), '2 + 3')).equals('2 + 3 = 5');
    });

    test('multiplies before it adds', () {
      check(invoke(calculatorTool(), '2 + 3 * 4')).contains('= 14');
    });

    test('honours brackets', () {
      check(invoke(calculatorTool(), '(2 + 3) * 4')).contains('= 20');
    });

    test('handles decimals and negatives', () {
      check(invoke(calculatorTool(), '12.5 - 20')).contains('= -7.5');
      check(invoke(calculatorTool(), '-4 * -3')).contains('= 12');
    });

    test('raises to a power, right to left', () {
      // 2^(3^2) = 512, not (2^3)^2 = 64.
      check(invoke(calculatorTool(), '2 ^ 3 ^ 2')).contains('= 512');
    });

    test('gets a long multiplication exactly right', () {
      // The sum the stress-test agent ships with — the kind a model guesses.
      check(invoke(calculatorTool(), '4821 * 37 - 1904')).contains('= 176473');
    });

    test('prints a whole number without a trailing zero', () {
      check(invoke(calculatorTool(), '10 / 2')).equals('10 / 2 = 5');
    });

    test('refuses words rather than dropping them', () {
      // `5 apples + 3` quietly becoming `5 + 3` is worse than an error: the
      // model would take the answer as confirmation it asked a sensible thing.
      check(invoke(calculatorTool(), '5 apples + 3')).contains('not an');
    });

    test('says so when it divides by zero', () {
      check(invoke(calculatorTool(), '1 / 0')).contains('divides by zero');
    });

    test('catches an unclosed bracket', () {
      check(invoke(calculatorTool(), '(2 + 3')).contains('unclosed');
    });

    test('catches an expression that stops in the middle', () {
      check(invoke(calculatorTool(), '2 +')).contains('stops in the middle');
    });

    test('never throws, whatever it is handed', () {
      for (final input in <String>['', '   ', ')(', '**', '1 2 3']) {
        check(
          () => invoke(calculatorTool(), input),
          because: input,
        ).returnsNormally();
      }
    });
  });

  group('date_math', () {
    ToolDefinition tool() =>
        dateMathTool(now: () => DateTime(2026, 10, 6, 14, 30));

    test('resolves today, ignoring the time of day', () {
      check(invoke(tool(), 'today')).equals('2026-10-06');
    });

    test('adds days', () {
      check(invoke(tool(), '2026-10-06 + 45 days')).contains('2026-11-20');
    });

    test('adds days to today, which is what the shipped agent asks', () {
      check(invoke(tool(), 'today + 93 days')).contains('2027-01-07');
    });

    test('subtracts weeks', () {
      check(invoke(tool(), '2026-10-06 - 3 weeks')).contains('2026-09-15');
    });

    test('adds months and years', () {
      check(invoke(tool(), '2026-10-06 + 4 months')).contains('2027-02-06');
      check(invoke(tool(), '2026-10-06 + 2 years')).contains('2028-10-06');
    });

    test('counts the days between two dates', () {
      check(invoke(tool(), 'days between 2026-01-01 and 2026-10-06'))
          .contains('278 days');
    });

    test('counts between a date and today', () {
      check(invoke(tool(), 'between 2026-10-01 and today')).contains('5 days');
    });

    test('crosses a leap day correctly', () {
      final leap = dateMathTool(now: () => DateTime(2028, 1, 1));
      check(invoke(leap, '2028-02-28 + 1 days')).contains('2028-02-29');
    });

    test('refuses a date it cannot read', () {
      check(invoke(tool(), 'next tuesday + 3 days')).contains('not a date');
    });

    test('never throws, whatever it is handed', () {
      for (final input in <String>['', 'tomorrow', '2026-13-45', 'x + y']) {
        check(() => invoke(tool(), input), because: input).returnsNormally();
      }
    });
  });

  group('unit_convert', () {
    test('converts length', () {
      check(invoke(unitConvertTool(), '10 km to miles')).contains('6.2137');
    });

    test('converts the miles the shipped agent asks for', () {
      check(invoke(unitConvertTool(), '72 miles to km')).contains('115.87');
    });

    test('converts mass', () {
      check(invoke(unitConvertTool(), '5 kg to pounds')).contains('11.023');
    });

    test('converts temperature, which is not a multiple', () {
      check(invoke(unitConvertTool(), '98.6 F to C')).contains('37');
      check(invoke(unitConvertTool(), '0 C to F')).contains('32');
      check(invoke(unitConvertTool(), '100 C to K')).contains('373.15');
    });

    test('accepts the spellings a model is likely to write', () {
      for (final input in <String>[
        '1 metre to centimetres',
        '1 meter to cm',
        '1 m in cm',
        '1 M to CM',
      ]) {
        check(invoke(unitConvertTool(), input), because: input).contains('100');
      }
    });

    test('refuses units that do not measure the same thing', () {
      check(invoke(unitConvertTool(), '10 km to kg'))
          .contains('do not measure the same thing');
    });

    test('refuses a unit it does not know', () {
      check(invoke(unitConvertTool(), '10 furlongs to km')).contains('furlong');
    });

    test('explains the shape it wants', () {
      check(invoke(unitConvertTool(), 'ten km in miles')).contains('10 km');
    });

    test('never throws, whatever it is handed', () {
      for (final input in <String>['', 'km', '5 to 6', '1 1 1']) {
        check(
          () => invoke(unitConvertTool(), input),
          because: input,
        ).returnsNormally();
      }
    });
  });
}
