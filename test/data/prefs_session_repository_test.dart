import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/repositories/local_session_repository.dart';
import 'package:model_scope_flutter/data/repositories/prefs_session_repository.dart';
import 'package:model_scope_flutter/data/repositories/session_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fakes.dart';

void main() {
  // The repository encodes and decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SessionRepository legacy;
  late PrefsSessionRepository repository;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    directory = await Directory.systemTemp.createTemp('model_scope_prefs');
    legacy = LocalSessionRepository(
      JsonFileStore(directory: directory, fileName: 'sessions.json'),
    );
    repository = PrefsSessionRepository(SharedPreferencesAsync(), legacy);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('returns an empty list before anything has been saved', () async {
    // Act
    final loaded = await repository.load();

    // Assert
    check(loaded).isEmpty();
  });

  test('round-trips a session with its transcript', () async {
    // Arrange
    final session = _session();

    // Act
    await repository.save(<ChatSession>[session]);
    final loaded = await repository.load();

    // Assert
    check(loaded).length.equals(1);
    check(loaded.first.id).equals(session.id);
    check(loaded.first.title).equals(session.title);
    check(loaded.first.createdAt).equals(session.createdAt);
    check(loaded.first.messages).length.equals(2);
    check(loaded.first.messages.first.role).equals(MessageRole.user);
  });

  test('does not persist the transient streaming flag', () async {
    // Arrange
    final session = _session().copyWith(
      messages: <ChatMessage>[
        ChatMessage(
          id: 'streaming',
          role: MessageRole.assistant,
          text: 'partial',
          createdAt: DateTime(2026, 9, 30, 12),
          isStreaming: true,
        ),
      ],
    );

    // Act
    await repository.save(<ChatSession>[session]);
    final loaded = await repository.load();

    // Assert
    check(loaded.first.messages.first.isStreaming).isFalse();
  });

  test('a later save replaces the whole document', () async {
    // Arrange
    await repository.save(<ChatSession>[_session(id: 'a'), _session(id: 'b')]);

    // Act — delete is modelled as saving the remaining list.
    await repository.save(<ChatSession>[_session(id: 'b')]);
    final loaded = await repository.load();

    // Assert
    check(loaded.map((s) => s.id).toList()).deepEquals(<String>['b']);
  });

  test('imports sessions.json on the first load after an upgrade', () async {
    // Arrange — the previous build's store, with nothing in preferences yet.
    await legacy.save(<ChatSession>[_session(id: 'carried-over')]);

    // Act
    final loaded = await repository.load();

    // Assert — the conversation survives the move.
    check(loaded.map((s) => s.id).toList())
        .deepEquals(<String>['carried-over']);
  });

  test('does not re-import once preferences hold the sessions', () async {
    // Arrange — migrate, then delete everything through the new store.
    await legacy.save(<ChatSession>[_session(id: 'carried-over')]);
    await repository.load();
    await repository.save(const <ChatSession>[]);

    // Act
    final loaded = await repository.load();

    // Assert — a deleted session must not come back from the old file, which
    // is left on disk as a fallback rather than removed.
    check(loaded).isEmpty();
  });

  test('a corrupt stored value falls back to an empty list', () async {
    // Arrange
    await SharedPreferencesAsync().setString('sessions', 'not json at all');

    // Act
    final loaded = await repository.load();

    // Assert — a bad value must not stop the app from opening.
    check(loaded).isEmpty();
  });

  test('skips an unreadable entry rather than losing the list', () async {
    // Arrange
    await SharedPreferencesAsync().setString(
      'sessions',
      '{"sessions":[{"id":42},{"id":"good","title":"Kept",'
          '"model_id":"m","created_at":"2026-09-30T12:08:00.000",'
          '"updated_at":"2026-09-30T12:11:00.000","messages":[]}]}',
    );

    // Act
    final loaded = await repository.load();

    // Assert
    check(loaded.map((s) => s.id).toList()).deepEquals(<String>['good']);
  });
}

ChatSession _session({String id = 'session-1'}) {
  final at = DateTime(2026, 9, 30, 12, 8);
  return ChatSession(
    id: id,
    title: 'Explain quantisation',
    modelId: fakeInstalledModel().id,
    createdAt: at,
    updatedAt: at.add(const Duration(minutes: 3)),
    messages: <ChatMessage>[
      ChatMessage(
        id: '$id-0',
        role: MessageRole.user,
        text: 'What does Q8_0 mean?',
        createdAt: at,
      ),
      ChatMessage(
        id: '$id-1',
        role: MessageRole.assistant,
        text: 'Eight-bit weights.',
        createdAt: at.add(const Duration(seconds: 2)),
      ),
    ],
  );
}
