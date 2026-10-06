/// Defensive readers for JSON the app does not own.
///
/// Tavily and Firecrawl both answer with large, versioned documents of which
/// this app wants a handful of fields. `json_serializable` is the wrong tool
/// for that: it would need a class per nesting level, and a field the provider
/// renames or drops would throw rather than degrade. These readers take the
/// field when it is the expected type and fall back when it is not, so a
/// response that changes shape costs a title, not the whole call.
library;

/// The string at [value], or [fallback] when it is absent or another type.
String readString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

/// The string at [value], or null when it is absent, another type, or empty —
/// so an optional field reads as missing rather than blank.
String? readStringOrNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The number at [value] as an int, or [fallback]. Accepts a double, because
/// JSON makes no promise about which side of the decimal point a count arrives
/// on.
int readInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

double readDouble(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : fallback;

bool readBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

/// The object at [value], or an empty map — which lets a caller read through a
/// missing nesting level without a null check at every step.
Map<String, dynamic> readMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

/// Every [Map] in the list at [value], skipping entries of any other type.
List<Map<String, dynamic>> readObjectList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final entry in value)
      if (entry is Map<String, dynamic>) entry,
  ];
}

/// Every non-empty string in the list at [value].
List<String> readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final entry in value)
      if (entry is String && entry.isNotEmpty) entry,
  ];
}
