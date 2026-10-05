import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import 'local_session_repository.dart';

/// Storage for chat sessions, backed by shared preferences.
/// [SharedPreferencesAsync] reads and writes on demand, so nothing has to be
/// primed in `main()`. Encoding and decoding run on [compute]: a transcript
/// grows without bound, unlike a preference flag.
class SessionRepository {
  const SessionRepository(this._prefs, this._legacy);

  final SharedPreferencesAsync _prefs;

  /// The store sessions used to live in. Read once, to migrate.
  final LocalSessionRepository _legacy;

  static const String _key = 'sessions';
  static const String _logName = 'SessionRepository';

  Future<List<ChatSession>> load() async {
    final raw = await _prefs.getString(_key);
    if (raw != null) return _parse(raw);

    // A first run, or an upgrade from the build that wrote sessions.json.
    final legacy = await _legacy.load();
    if (legacy.isEmpty) return legacy;
    developer.log(
      'Imported ${legacy.length} sessions from sessions.json',
      name: _logName,
    );
    await save(legacy);
    return legacy;
  }

  Future<void> save(List<ChatSession> sessions) async {
    final document = <String, dynamic>{
      _key: sessions.map((s) => s.toJson()).toList(),
    };
    await _prefs.setString(_key, await compute(jsonEncode, document));
  }

  /// Turns a stored document back into sessions, skipping any single one that
  /// will not parse rather than losing the whole list to it.
  static Future<List<ChatSession>> _parse(String raw) async {
    final decoded = await compute(_decode, raw);
    final entries = decoded?[_key];
    if (entries is! List) return const <ChatSession>[];

    final sessions = <ChatSession>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        sessions.add(ChatSession.fromJson(entry));
      } catch (error, stackTrace) {
        developer.log(
          'Dropped an unreadable session',
          name: _logName,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return sessions;
  }
}

/// Returns null when the stored string is not a JSON object, so a corrupt
/// value reads as "nothing saved" instead of taking the app down on launch.
Map<String, dynamic>? _decode(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
