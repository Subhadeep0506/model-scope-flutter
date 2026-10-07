import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/generation_metrics.dart';
import 'package:model_scope_flutter/data/models/usage_record.dart';
import 'package:model_scope_flutter/data/repositories/usage_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

void main() {
  // The store encodes and decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late UsageRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('usage_test');
    repository = UsageRepository(
      JsonFileStore(directory: directory, fileName: 'usage.json'),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  final DateTime now = DateTime(2026, 10, 7, 12);

  UsageRecord record({
    DateTime? at,
    String modelId = 'acme/small.gguf',
    String modelName = 'Small',
    String? paramLabel = '360M',
    int tokenCount = 40,
    int latencyMs = 100,
    double tokensPerSecond = 50,
    UsageKind kind = UsageKind.chat,
  }) => UsageRecord(
    at: at ?? now,
    modelId: modelId,
    modelName: modelName,
    paramLabel: paramLabel,
    quantization: 'Q8_0',
    tokenCount: tokenCount,
    latencyMs: latencyMs,
    tokensPerSecond: tokensPerSecond,
    kind: kind,
  );

  test('a store that has never been written reads as empty', () async {
    final ledger = await repository.load();

    check(ledger.isEmpty).isTrue();
    check(ledger.migrated).isFalse();
    check(ledger.totals.replies).equals(0);
  });

  test('a record survives a round trip through the file', () async {
    await repository.add(record(tokenCount: 30, latencyMs: 120));

    final ledger = await repository.load();

    check(ledger.totals.replies).equals(1);
    check(ledger.totals.tokens).equals(30);
    check(ledger.totals.averageLatencyMs).equals(120);
    check(ledger.recent.single.modelName).equals('Small');
    check(ledger.byModel['acme/small.gguf']?.replies).equals(1);
    check(ledger.byModel['acme/small.gguf']?.paramLabel).equals('360M');
  });

  test('totals accumulate across separate writes', () async {
    await repository.add(record(tokenCount: 30, latencyMs: 100));
    await repository.add(record(tokenCount: 70, latencyMs: 300));

    final ledger = await repository.load();

    check(ledger.totals.replies).equals(2);
    check(ledger.totals.tokens).equals(100);
    check(ledger.totals.averageLatencyMs).equals(200);
  });

  test('the peak keeps the model that set it', () async {
    await repository.add(record(tokensPerSecond: 94.2));
    await repository.add(
      record(
        modelId: 'acme/large.gguf',
        modelName: 'Large',
        tokensPerSecond: 41,
      ),
    );

    final totals = (await repository.load()).totals;

    check(totals.peakTokensPerSecond).equals(94.2);
    check(totals.peakModelName).equals('Small');
  });

  test('agent runs are counted apart from replies', () async {
    await repository.add(record());
    await repository.add(record(kind: UsageKind.agentRun, tokenCount: 0));

    final totals = (await repository.load()).totals;

    check(totals.agentRuns).equals(1);
    check(totals.replies).equals(2);
  });

  test('ageing out a record does not lower the lifetime totals', () async {
    // The whole point of splitting totals from records: the day-by-day chart
    // only needs recent rows, and pruning them must not rewrite history.
    final old = record(at: now.subtract(const Duration(days: 90)));
    await repository.save(UsageLedger.empty.plus(old).plus(record()));

    final ledger = await repository.load();

    check(ledger.recent).length.equals(1);
    check(ledger.totals.replies).equals(2);
    check(ledger.totals.tokens).equals(80);
  });

  group('importOnce', () {
    ChatSession sessionWith(List<ChatMessage> messages) => ChatSession(
      id: 's1',
      title: 'Quant notes',
      modelId: 'acme/small.gguf',
      createdAt: now,
      updatedAt: now,
      messages: messages,
    );

    ChatMessage reply(String id, int tokens) => ChatMessage(
      id: id,
      role: MessageRole.assistant,
      text: 'answer',
      createdAt: now,
      metrics: GenerationMetrics(
        latencyMs: 100,
        tokensPerSecond: 50,
        tokenCount: tokens,
      ),
    );

    test('folds already-stored replies in and marks the ledger done', () async {
      final records = recordsFromSessions(<ChatSession>[
        sessionWith(<ChatMessage>[reply('r1', 30), reply('r2', 70)]),
      ]);

      final ledger = await repository.importOnce(records);

      check(ledger.migrated).isTrue();
      check(ledger.totals.replies).equals(2);
      check(ledger.totals.tokens).equals(100);
    });

    test('runs once, so a second launch does not double the figures', () async {
      final records = recordsFromSessions(<ChatSession>[
        sessionWith(<ChatMessage>[reply('r1', 30)]),
      ]);

      await repository.importOnce(records);
      final second = await repository.importOnce(records);

      check(second.totals.replies).equals(1);
      check(second.totals.tokens).equals(30);
    });

    test('an import of nothing still settles the flag', () async {
      // Otherwise a device that had never chatted would re-read every
      // session on every launch, for ever.
      check((await repository.importOnce(const <UsageRecord>[])).migrated)
          .isTrue();
    });
  });

  group('recordsFromSessions', () {
    test('takes finished replies and leaves everything else', () {
      final records = recordsFromSessions(<ChatSession>[
        ChatSession(
          id: 's1',
          title: 'T',
          modelId: 'acme/small.gguf',
          createdAt: now,
          updatedAt: now,
          messages: <ChatMessage>[
            // A question carries no metrics and is not a reply.
            ChatMessage(
              id: 'q',
              role: MessageRole.user,
              text: 'ask',
              createdAt: now,
            ),
            // A reply that failed has no throughput worth averaging.
            ChatMessage(
              id: 'bad',
              role: MessageRole.assistant,
              text: '',
              createdAt: now,
              error: 'it broke',
              metrics: const GenerationMetrics(
                latencyMs: 10,
                tokensPerSecond: 1,
                tokenCount: 1,
              ),
            ),
            ChatMessage(
              id: 'good',
              role: MessageRole.assistant,
              text: 'answer',
              createdAt: now,
              metrics: const GenerationMetrics(
                latencyMs: 100,
                tokensPerSecond: 50,
                tokenCount: 40,
              ),
            ),
          ],
        ),
      ]);

      check(records).length.equals(1);
      check(records.single.tokenCount).equals(40);
      check(records.single.modelId).equals('acme/small.gguf');
    });

    test('comes back oldest first, whatever order the sessions were in', () {
      ChatSession at(String id, DateTime when) => ChatSession(
        id: id,
        title: id,
        modelId: 'm',
        createdAt: when,
        updatedAt: when,
        messages: <ChatMessage>[
          ChatMessage(
            id: '$id-r',
            role: MessageRole.assistant,
            text: 'a',
            createdAt: when,
            metrics: const GenerationMetrics(
              latencyMs: 1,
              tokensPerSecond: 1,
              tokenCount: 1,
            ),
          ),
        ],
      );

      final records = recordsFromSessions(<ChatSession>[
        at('newer', DateTime(2026, 10, 5)),
        at('older', DateTime(2026, 10, 1)),
      ]);

      check(records.first.at).equals(DateTime(2026, 10, 1));
      check(records.last.at).equals(DateTime(2026, 10, 5));
    });
  });
}
