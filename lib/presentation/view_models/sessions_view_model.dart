import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../data/models/chat_session.dart';

class SessionsViewModel extends AsyncNotifier<List<ChatSession>> {
  static const String untitled = 'New chat';
  static const Uuid _uuid = Uuid();
  @override
  Future<List<ChatSession>> build() async =>
      _sorted(await ref.read(sessionRepositoryProvider).load());

  Future<ChatSession> create() async {
    final session = _blank();
    await _write(<ChatSession>[session, ..._current]);
    return session;
  }

  Future<void> delete(String id) async {
    final doomed = byId(id);
    await _write(_current.where((s) => s.id != id).toList());
    if (doomed == null) return;
    await ref.read(imageStoreProvider).delete(<String>[
      for (final message in doomed.messages) ...message.imagePaths,
    ]);
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
