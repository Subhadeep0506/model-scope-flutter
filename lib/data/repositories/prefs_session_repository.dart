import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import 'session_repository.dart';

/// [SessionRepository] backed by shared preferences.
///
/// Uses [SharedPreferencesAsync] rather than the older `getInstance()` cache:
/// it reads and writes on demand, so nothing has to be primed in `main()`, and
/// on Android it is backed by DataStore — which keeps the atomic write the
/// earlier `sessions.json` store got from a temp-file rename.
///
/// Encoding and decoding still run on [compute]. A transcript grows without
/// bound and this is a whole conversation history, not a preference flag.
class PrefsSessionRepository implements SessionRepository {
  const PrefsSessionRepository(this._prefs, this._legacy);

  final SharedPreferencesAsync _prefs;

  /// The store sessions used to live in. Read once, to migrate.
  final SessionRepository _legacy;

  static const String _key = 'sessions';
  static const String _logName = 'PrefsSessionRepository';

  @override
  Future<List<ChatSession>> load() async {
    final raw = await _prefs.getString(_key);
    if (raw != null) return _parse(raw);

    // Nothing stored here yet: either a first run, or an upgrade from the
    // build that wrote sessions.json. Importing costs one file read on a cold
    // start and only happens until the first save lands.
    final legacy = await _legacy.load();
    if (legacy.isEmpty) return legacy;
    developer.log(
      'Imported ${legacy.length} sessions from sessions.json',
      name: _logName,
    );
    await save(legacy);
    return legacy;
  }

  @override
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
