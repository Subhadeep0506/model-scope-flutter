import 'dart:developer' as developer;

import '../models/chat_session.dart';
import '../sources/json_file_store.dart';

/// The `sessions.json` file chat sessions used to live in. Kept only as the
/// migration source `SessionRepository` reads once, on an upgrade.
class LocalSessionRepository {
  const LocalSessionRepository(this._store);

  final JsonFileStore _store;

  static const String _sessionsKey = 'sessions';

  Future<List<ChatSession>> load() async {
    final document = await _store.read();
    final raw = document?[_sessionsKey];
    if (raw is! List) return const <ChatSession>[];

    final sessions = <ChatSession>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        sessions.add(ChatSession.fromJson(entry));
      } catch (error, stackTrace) {
        // Skip a single unreadable session rather than losing the whole list.
        developer.log(
          'Dropped an unreadable session',
          name: 'LocalSessionRepository',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return sessions;
  }

  Future<void> save(List<ChatSession> sessions) => _store.write(
    <String, dynamic>{_sessionsKey: sessions.map((s) => s.toJson()).toList()},
  );
}
