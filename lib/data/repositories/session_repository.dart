import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import 'local_session_repository.dart';

class SessionRepository {
  const SessionRepository(this._prefs, this._legacy);
  final SharedPreferencesAsync _prefs;
  final LocalSessionRepository _legacy;

  static const String _key = 'sessions';
  static const String _logName = 'SessionRepository';

  Future<List<ChatSession>> load() async {
    final raw = await _prefs.getString(_key);
    if (raw != null) return _parse(raw);

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

Map<String, dynamic>? _decode(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
