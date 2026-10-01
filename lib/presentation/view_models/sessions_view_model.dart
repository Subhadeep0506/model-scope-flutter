import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../data/models/chat_session.dart';

/// Owns the list of conversations shown on the Chats screen.
///
/// Every mutation writes the whole list back to disk, which is cheap at this
/// scale and keeps the on-disk document and the in-memory list from drifting.
class SessionsViewModel extends AsyncNotifier<List<ChatSession>> {
  static const String untitled = 'New chat';

  static const Uuid _uuid = Uuid();

  @override
  Future<List<ChatSession>> build() async {
    final stored = await ref.read(sessionRepositoryProvider).load();
    if (stored.isNotEmpty) return _sorted(stored);

    // First launch: seed one session so the list is never empty.
    final seed = _blank();
    await ref.read(sessionRepositoryProvider).save(<ChatSession>[seed]);
    return <ChatSession>[seed];
  }

  /// Creates an empty session and returns it so the caller can navigate to it.
  Future<ChatSession> create() async {
    final session = _blank();
    await _write(<ChatSession>[session, ..._current]);
    return session;
  }

  Future<void> delete(String id) async {
    await _write(_current.where((s) => s.id != id).toList());
  }

  /// Puts a deleted session back, used by the undo action.
  Future<void> restore(ChatSession session) async {
    await _write(<ChatSession>[session, ..._current]);
  }

  /// Replaces a session in place, or appends it if it is not in the list.
  Future<void> upsert(ChatSession session) async {
    final next = _current.where((s) => s.id != session.id).toList()
      ..add(session);
    await _write(next);
  }

  ChatSession? byId(String id) {
    for (final session in _current) {
      if (session.id == id) return session;
    }
    return null;
  }

  List<ChatSession> get _current => state.value ?? const <ChatSession>[];

  ChatSession _blank() {
    final now = DateTime.now();
    return ChatSession(
      id: _uuid.v4(),
      title: untitled,
      // Empty when nothing is installed. The session is still created so the
      // chat screen can open and explain why; it is stamped with whichever
      // model answers once one exists.
      modelId: ref.read(activeModelProvider)?.id ?? '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _write(List<ChatSession> sessions) async {
    final sorted = _sorted(sessions);
    state = AsyncData<List<ChatSession>>(sorted);
    await ref.read(sessionRepositoryProvider).save(sorted);
  }

  /// Most recently touched first, matching the Chats list.
  static List<ChatSession> _sorted(Iterable<ChatSession> sessions) =>
      sessions.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
