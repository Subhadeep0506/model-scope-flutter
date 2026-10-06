/// The tools that need nothing but the device: arithmetic, date arithmetic and
/// unit conversion.
///
/// They matter out of proportion to their size. Every other tool in this build
/// needs an API key, so without these a fresh install cannot run an agent at
/// all — and these three are also the cleanest probe of the thing this app
/// exists to measure, because a wrong answer is unambiguous. A model that
/// claims `17 * 24 = 418` has failed in a way no web search result can argue
/// with.
///
/// Each follows the same rules as the web tools: one required named `String`,
/// never throws, and returns a sentence the model can read.
library;

import 'dart:math' as math;

import 'tool_definition.dart';

/// Works out an arithmetic expression.
ToolDefinition calculatorTool() {
  String run({required String expression}) {
    try {
      return '$expression = ${_formatNumber(_evaluate(expression))}';
    } on FormatException catch (error) {
      return 'That is not an expression this calculator can work out: '
          '${error.message}';
    }
  }

  return ToolDefinition(
    name: 'calculator',
    description:
        'Work out an arithmetic expression exactly. Use this for any sum, '
        'however simple — do not do arithmetic in your head. Handles + - * / '
        'and ^, brackets, and decimals.',
    function: run,
    parameterDescriptions: const <String, String>{
      'expression':
          'The sum to work out, for example (12.5 + 7) * 3. Digits '
          'and operators only, with no words and no units.',
    },
  );
}

/// Adds to or subtracts from a date, or measures the gap between two.
ToolDefinition dateMathTool({DateTime Function()? now}) {
  final clock = now ?? DateTime.now;

  String run({required String expression}) {
    try {
      return _dateAnswer(expression, clock());
    } on FormatException catch (error) {
      return 'That is not a date question this tool can answer: '
          '${error.message}';
    }
  }

  return ToolDefinition(
    name: 'date_math',
    description:
        'Work out a date exactly. Use this rather than counting days '
        'yourself. Understands "today", "2026-10-06 + 45 days", '
        '"2026-10-06 - 3 weeks" and "days between 2026-01-01 and today".',
    function: run,
    parameterDescriptions: const <String, String>{
      'expression':
          'The date question, for example 2026-10-06 + 45 days. '
          'Write dates as YYYY-MM-DD, or use the word today.',
    },
  );
}

/// Converts a measurement from one unit to another.
ToolDefinition unitConvertTool() {
  String run({required String expression}) {
    try {
      return _convertAnswer(expression);
    } on FormatException catch (error) {
      return 'That is not a conversion this tool can do: ${error.message}';
    }
  }

  return ToolDefinition(
    name: 'unit_convert',
    description:
        'Convert a measurement between units. Use this instead of converting '
        'from memory. Handles length, mass, volume and temperature, for '
        'example "10 km to miles" or "98.6 F to C".',
    function: run,
    parameterDescriptions: const <String, String>{
      'expression':
          'The conversion, as <number> <from unit> to <to unit>, '
          'for example 10 km to miles.',
    },
  );
}

// ---------------------------------------------------------------- arithmetic

/// Splits [input] into numbers, operators and brackets. Anything else is
/// refused here rather than being silently dropped, so `5 apples + 3` is an
/// error instead of quietly becoming `5 + 3`.
List<String> _tokenize(String input) {
  final tokens = <String>[];
  final pattern = RegExp(r'\d*\.?\d+|[-+*/^()]');

  var index = 0;
  while (index < input.length) {
    if (input[index].trim().isEmpty) {
      index++;
      continue;
    }
    final match = pattern.matchAsPrefix(input, index);
    if (match == null) {
      throw FormatException('"${input[index]}" is not a number or an operator');
    }
    tokens.add(match.group(0) ?? '');
    index = match.end;
  }
  if (tokens.isEmpty) {
    throw const FormatException('there was nothing to work out');
  }
  return tokens;
}

double _evaluate(String input) {
  final parser = _ExpressionParser(_tokenize(input));
  final value = parser.parse();
  if (!value.isFinite) {
    throw const FormatException('the result is not a finite number');
  }
  return value;
}

/// A recursive-descent parser over the token list: sums, then products, then
/// powers, then single values. Each level consumes only what binds tighter
/// than it, which is what gives `2 + 3 * 4` the value 14 rather than 20.
class _ExpressionParser {
  _ExpressionParser(this._tokens);

  final List<String> _tokens;
  int _at = 0;

  String? get _peek => _at < _tokens.length ? _tokens[_at] : null;

  double parse() {
    final value = _sum();
    if (_at < _tokens.length) {
      throw FormatException('"${_tokens[_at]}" is in the wrong place');
    }
    return value;
  }

  double _sum() {
    var value = _product();
    while (_peek == '+' || _peek == '-') {
      final operator = _tokens[_at++];
      final right = _product();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  double _product() {
    var value = _power();
    while (_peek == '*' || _peek == '/') {
      final operator = _tokens[_at++];
      final right = _power();
      if (operator == '/' && right == 0) {
        throw const FormatException('it divides by zero');
      }
      value = operator == '*' ? value * right : value / right;
    }
    return value;
  }

  /// Right-associative, so `2^3^2` is 2^9 and not 8^2.
  double _power() {
    final base = _value();
    if (_peek != '^') return base;
    _at++;

    // A fractional power of a negative number has no real answer, and `pow`
    // reports that as NaN rather than raising.
    final result = math.pow(base, _power()).toDouble();
    if (result.isNaN) {
      throw const FormatException('that power has no real answer');
    }
    return result;
  }

  double _value() {
    final token = _peek;
    if (token == null) {
      throw const FormatException('it stops in the middle');
    }
    if (token == '-') {
      _at++;
      return -_value();
    }
    if (token == '+') {
      _at++;
      return _value();
    }
    if (token == '(') {
      _at++;
      final inner = _sum();
      if (_peek != ')') throw const FormatException('a bracket is unclosed');
      _at++;
      return inner;
    }
    final number = double.tryParse(token);
    if (number == null) {
      throw FormatException('"$token" is in the wrong place');
    }
    _at++;
    return number;
  }
}

/// Prints a result without a trailing `.0`, and without fifteen decimals of
/// floating-point noise.
String _formatNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toStringAsFixed(0);
  }
  final rounded = double.parse(value.toStringAsPrecision(10));
  return rounded.toString();
}

// --------------------------------------------------------------------- dates

/// `days between A and B`, or `A + n units`, or just a date.
String _dateAnswer(String input, DateTime now) {
  final text = input.trim().toLowerCase();
  if (text.isEmpty) {
    throw const FormatException('there was nothing to work out');
  }

  final between = RegExp(r'^(?:days\s+)?between\s+(.+?)\s+and\s+(.+)$')
      .firstMatch(text);
  if (between != null) {
    final from = _parseDate(between.group(1) ?? '', now);
    final to = _parseDate(between.group(2) ?? '', now);
    final days = to.difference(from).inDays;
    return '${_formatDate(from)} to ${_formatDate(to)} is ${days.abs()} days';
  }

  final shift = RegExp(r'^(.+?)\s*([+-])\s*(\d+)\s*(day|week|month|year)s?$')
      .firstMatch(text);
  if (shift != null) return _shiftAnswer(shift, now);

  return _formatDate(_parseDate(text, now));
}

String _shiftAnswer(RegExpMatch shift, DateTime now) {
  final start = _parseDate(shift.group(1) ?? '', now);
  final sign = shift.group(2) == '-' ? -1 : 1;
  final amount = sign * (int.tryParse(shift.group(3) ?? '') ?? 0);

  final moved = switch (shift.group(4)) {
    'day' => start.add(Duration(days: amount)),
    'week' => start.add(Duration(days: amount * 7)),
    'month' => DateTime(start.year, start.month + amount, start.day),
    _ => DateTime(start.year + amount, start.month, start.day),
  };
  return '${_formatDate(start)} ${shift.group(2)} ${shift.group(3)} '
      '${shift.group(4)}s is ${_formatDate(moved)}';
}

/// `today`, `tomorrow`, `yesterday` or an ISO date. Time of day is dropped —
/// every question this tool answers is about whole days.
DateTime _parseDate(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final trimmed = text.trim();

  return switch (trimmed) {
    'today' || 'now' => today,
    'tomorrow' => today.add(const Duration(days: 1)),
    'yesterday' => today.subtract(const Duration(days: 1)),
    _ => _parseIsoDate(trimmed),
  };
}

DateTime _parseIsoDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
  if (match == null) {
    throw FormatException('"$text" is not a date — write it as YYYY-MM-DD');
  }
  return DateTime(
    int.parse(match.group(1) ?? '0'),
    int.parse(match.group(2) ?? '1'),
    int.parse(match.group(3) ?? '1'),
  );
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// --------------------------------------------------------------------- units

/// One unit, as a multiple of its dimension's base unit — metre, kilogram,
/// litre. Temperature is not a multiple of anything, so it is handled apart.
typedef _Unit = ({String dimension, double factor, String name});

const Map<String, _Unit> _units = <String, _Unit>{
  'mm': (dimension: 'length', factor: 0.001, name: 'millimetres'),
  'cm': (dimension: 'length', factor: 0.01, name: 'centimetres'),
  'm': (dimension: 'length', factor: 1, name: 'metres'),
  'km': (dimension: 'length', factor: 1000, name: 'kilometres'),
  'in': (dimension: 'length', factor: 0.0254, name: 'inches'),
  'ft': (dimension: 'length', factor: 0.3048, name: 'feet'),
  'yd': (dimension: 'length', factor: 0.9144, name: 'yards'),
  'mi': (dimension: 'length', factor: 1609.344, name: 'miles'),
  'mg': (dimension: 'mass', factor: 0.000001, name: 'milligrams'),
  'g': (dimension: 'mass', factor: 0.001, name: 'grams'),
  'kg': (dimension: 'mass', factor: 1, name: 'kilograms'),
  't': (dimension: 'mass', factor: 1000, name: 'tonnes'),
  'oz': (dimension: 'mass', factor: 0.028349523125, name: 'ounces'),
  'lb': (dimension: 'mass', factor: 0.45359237, name: 'pounds'),
  'ml': (dimension: 'volume', factor: 0.001, name: 'millilitres'),
  'l': (dimension: 'volume', factor: 1, name: 'litres'),
  'gal': (dimension: 'volume', factor: 3.785411784, name: 'US gallons'),
  'c': (dimension: 'temperature', factor: 1, name: 'degrees Celsius'),
  'f': (dimension: 'temperature', factor: 1, name: 'degrees Fahrenheit'),
  'k': (dimension: 'temperature', factor: 1, name: 'kelvin'),
};

/// The spellings a model is likely to write, mapped onto the table's keys.
const Map<String, String> _unitAliases = <String, String>{
  'millimeter': 'mm',
  'millimetre': 'mm',
  'centimeter': 'cm',
  'centimetre': 'cm',
  'meter': 'm',
  'metre': 'm',
  'kilometer': 'km',
  'kilometre': 'km',
  'inch': 'in',
  'inche': 'in',
  'foot': 'ft',
  'feet': 'ft',
  'yard': 'yd',
  'mile': 'mi',
  'milligram': 'mg',
  'gram': 'g',
  'kilogram': 'kg',
  'kilo': 'kg',
  'tonne': 't',
  'ton': 't',
  'ounce': 'oz',
  'pound': 'lb',
  'lbs': 'lb',
  'milliliter': 'ml',
  'millilitre': 'ml',
  'liter': 'l',
  'litre': 'l',
  'gallon': 'gal',
  'celsius': 'c',
  'centigrade': 'c',
  'fahrenheit': 'f',
  'kelvin': 'k',
};

String _convertAnswer(String input) {
  final match = RegExp(
    r'^\s*(-?\d*\.?\d+)\s*([a-z°]+)\s+(?:to|in|into|as)\s+([a-z°]+)\s*$',
    caseSensitive: false,
  ).firstMatch(input.trim());
  if (match == null) {
    throw const FormatException(
      'write it as <number> <unit> to <unit>, for example 10 km to miles',
    );
  }

  final amount = double.tryParse(match.group(1) ?? '');
  if (amount == null) throw const FormatException('the number is unreadable');

  final from = _unitNamed(match.group(2) ?? '');
  final to = _unitNamed(match.group(3) ?? '');
  if (from.dimension != to.dimension) {
    throw FormatException(
      '${from.name} and ${to.name} do not measure the same thing',
    );
  }

  final result = from.dimension == 'temperature'
      ? _convertTemperature(amount, match.group(2) ?? '', match.group(3) ?? '')
      : amount * from.factor / to.factor;
  return '$amount ${from.name} is ${_formatNumber(result)} ${to.name}';
}

/// The table entry for [text], after stripping a plural and a degree sign and
/// trying the alias list.
_Unit _unitNamed(String text) {
  final cleaned = text.toLowerCase().replaceAll('°', '').trim();
  final candidates = <String>[
    cleaned,
    _unitAliases[cleaned] ?? '',
    if (cleaned.endsWith('s')) ...<String>[
      cleaned.substring(0, cleaned.length - 1),
      _unitAliases[cleaned.substring(0, cleaned.length - 1)] ?? '',
    ],
  ];

  for (final candidate in candidates) {
    final unit = _units[candidate];
    if (unit != null) return unit;
  }
  throw FormatException('"$text" is not a unit this tool knows');
}

/// Through Celsius, which keeps three scales to two conversions each rather
/// than six.
double _convertTemperature(double amount, String from, String to) {
  final fromKey = _unitKey(from);
  final toKey = _unitKey(to);

  final celsius = switch (fromKey) {
    'f' => (amount - 32) * 5 / 9,
    'k' => amount - 273.15,
    _ => amount,
  };
  return switch (toKey) {
    'f' => celsius * 9 / 5 + 32,
    'k' => celsius + 273.15,
    _ => celsius,
  };
}

String _unitKey(String text) {
  final cleaned = text.toLowerCase().replaceAll('°', '').trim();
  if (_units.containsKey(cleaned)) return cleaned;
  return _unitAliases[cleaned] ?? cleaned;
}
