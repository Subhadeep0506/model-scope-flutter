import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/generation_metrics.dart';
import 'package:model_scope_flutter/data/repositories/local_session_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

import '../support/fakes.dart';

void main() {
  // `JsonFileStore` encodes and decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late LocalSessionRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_scope_sessions');
    repository = LocalSessionRepository(
      JsonFileStore(directory: directory, fileName: 'sessions.json'),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('returns an empty list before anything has been saved', () async {
    final loaded = await repository.load();

    check(loaded).isEmpty();
  });

  test('round-trips a session with its transcript and metrics', () async {
    final session = _session();

    await repository.save(<ChatSession>[session]);
    final loaded = await repository.load();

    check(loaded).length.equals(1);
    final restored = loaded.first;
    check(restored.id).equals(session.id);
    check(restored.title).equals(session.title);
    check(restored.createdAt).equals(session.createdAt);
    check(restored.messages).length.equals(2);
    check(restored.messages.first.role).equals(MessageRole.user);
    check(restored.messages.last.metrics?.tokenCount).equals(96);
  });

  test('does not persist the transient streaming flag', () async {
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

    await repository.save(<ChatSession>[session]);
    final loaded = await repository.load();

    check(loaded.first.messages.first.isStreaming).isFalse();
  });

  test('a later save replaces the whole document', () async {
    final first = _session(id: 'a');
    final second = _session(id: 'b');
    await repository.save(<ChatSession>[first, second]);

    // Delete is modelled as saving the remaining list.
    await repository.save(<ChatSession>[second]);
    final loaded = await repository.load();

    check(loaded.map((s) => s.id).toList()).deepEquals(<String>['b']);
  });

  test('skips an unreadable entry rather than losing the list', () async {
    final good = _session(id: 'good');
    await repository.save(<ChatSession>[good]);
    final file = File(
      '${directory.path}${Platform.pathSeparator}sessions.json',
    );
    final raw = await file.readAsString();
    await file.writeAsString(
      raw.replaceFirst('{"id":"good"', '{"id":42,"broken":true,"ignored":"'),
    );

    final loaded = await repository.load();

    // A malformed entry is dropped, the read itself still succeeds.
    check(loaded).isEmpty();
  });

  test('a corrupt file falls back to an empty list', () async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}sessions.json',
    );
    await file.writeAsString('not json at all');

    final loaded = await repository.load();

    check(loaded).isEmpty();
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
        imagePaths: const <String>['/app/images/notes.png'],
      ),
      ChatMessage(
        id: '$id-1',
        role: MessageRole.assistant,
        text: 'Eight-bit weights.',
        createdAt: at.add(const Duration(seconds: 2)),
        metrics: const GenerationMetrics(
          latencyMs: 118,
          tokensPerSecond: 93.4,
          tokenCount: 96,
        ),
      ),
    ],
  );
}
