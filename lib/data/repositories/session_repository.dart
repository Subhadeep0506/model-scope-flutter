import '../models/chat_session.dart';

/// Storage for chat sessions.
abstract interface class SessionRepository {
  Future<List<ChatSession>> load();

  Future<void> save(List<ChatSession> sessions);
}
