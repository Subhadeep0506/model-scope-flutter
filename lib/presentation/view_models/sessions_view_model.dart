import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../data/models/chat_session.dart';

/// Owns the list of conversations shown on the Chats screen. Every change
/// writes the whole list back, which is cheap at this scale and keeps the
/// stored document and the in-memory list from drifting.
class SessionsViewModel extends AsyncNotifier<List<ChatSession>> {
  static const String untitled = 'New chat';

  static const Uuid _uuid = Uuid();

  /// Nothing is seeded on a first launch: an empty Chats list says plainly
  /// that there are no chats, where a blank "New chat" row only looked like
  /// one the user had forgotten starting. The screen offers a button instead.
  @override
  Future<List<ChatSession>> build() async =>
      _sorted(await ref.read(sessionRepositoryProvider).load());

  /// Creates an empty session and returns it so the caller can navigate to it.
  Future<ChatSession> create() async {
    final session = _blank();
    await _write(<ChatSession>[session, ..._current]);
    return session;
  }

  /// Deletes a session and the images its messages held — nothing else can be
  /// pointing at them, so leaving the copies behind would only orphan them.
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
      // Empty when nothing is installed; the session is still created so the
      // chat screen can open and explain why.
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
