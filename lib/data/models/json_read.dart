library;

String readString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

String? readStringOrNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int readInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

double readDouble(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : fallback;

bool readBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

Map<String, dynamic> readMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<Map<String, dynamic>> readObjectList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final entry in value)
      if (entry is Map<String, dynamic>) entry,
  ];
}

List<String> readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final entry in value)
      if (entry is String && entry.isNotEmpty) entry,
  ];
}
