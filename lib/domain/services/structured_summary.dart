import 'dart:convert';

import '../../data/models/json_read.dart';

/// The one line RUN HISTORY prints for a structured run.
///
/// Pure Dart with no Flutter in sight, because it is called from the runner
/// and stored on the run record — the widget that draws the same data lives in
/// the presentation layer and never meets this. The two are keyed by the same
/// view names, which is the only thing holding them together.
///
/// Returns null when [output] is not JSON or the view has nothing worth
/// saying, and the run record falls back to the first line of the output.
String? summariseStructured(String? view, String output) {
  final data = decodeStructured(output);
  if (data == null) return null;

  return switch (view) {
    'price_table' => _price(data),
    'weather_forecast' => _weather(data),
    _ => _generic(data),
  };
}

/// [output] as a JSON object, or null when it is not one.
///
/// Shared with the widgets, so what the history line summarises and what the
/// screen draws can never disagree about whether a run was structured.
Map<String, dynamic>? decodeStructured(String output) {
  final trimmed = output.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    // A constrained answer cut short by the context running out lands here.
    return null;
  }
}

/// `Cheapest: Retailer C · 4 offers`.
String? _price(Map<String, dynamic> data) {
  final offers = readObjectList(data['offers']);
  final cheapest = readStringOrNull(data['cheapest_retailer']);
  final count = '${offers.length} ${offers.length == 1 ? 'offer' : 'offers'}';
  return cheapest == null ? count : 'Cheapest: $cheapest · $count';
}

/// `Warmest: Tokyo · 3 places`.
String? _weather(Map<String, dynamic> data) {
  final places = readObjectList(data['places']);
  final warmest = readStringOrNull(data['warmest']);
  final count = '${places.length} ${places.length == 1 ? 'place' : 'places'}';
  return warmest == null ? count : 'Warmest: $warmest · $count';
}

/// What an agent nobody wrote a summary for gets: the fields it filled in.
String? _generic(Map<String, dynamic> data) {
  if (data.isEmpty) return null;
  final names = data.keys.take(3).join(', ');
  return data.length <= 3 ? names : '$names and ${data.length - 3} more';
}
