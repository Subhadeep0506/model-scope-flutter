import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/repositories/agent_run_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

void main() {
  // The store encodes and decodes on `compute`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AgentRunRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent_run_repository_test');
    repository = AgentRunRepository(
      JsonFileStore(directory: root, fileName: 'agent_runs.json'),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  AgentRun runOf(
    String id, {
    String agentId = 'web_answer',
    int durationMs = 4240,
    String output = 'An answer.',
    String? error,
    List<TraceEntry> trace = const <TraceEntry>[],
  }) => AgentRun(
    id: id,
    agentId: agentId,
    agentName: 'Web Answer',
    modelId: 'qwen25-15b',
    startedAt: DateTime(2026, 10, 6, 9),
    durationMs: durationMs,
    output: output,
    error: error,
    trace: trace,
  );

  test('nothing saved reads as no runs', () async {
    check(await repository.load()).isEmpty();
  });

  test('a run survives being written and read back', () async {
    await repository.add(
      runOf(
        'r1',
        trace: const <TraceEntry>[
          TraceEntry(
            kind: TraceKind.tool,
            label: 'web_search("dart")',
            durationMs: 312,
          ),
          TraceEntry(kind: TraceKind.answer, label: 'Final answer'),
        ],
      ),
    );

    final stored = (await repository.load()).single;

    check(stored.id).equals('r1');
    check(stored.startedAt).equals(DateTime(2026, 10, 6, 9));
    check(stored.trace).length.equals(2);
    check(stored.trace.first.label).equals('web_search("dart")');
    check(stored.trace.first.durationMs).equals(312);
    check(stored.trace.last.kind).equals(TraceKind.answer);
  });

  test('newest first, which is the order the history card wants', () async {
    await repository.add(runOf('first'));
    await repository.add(runOf('second'));

    check((await repository.load()).map((run) => run.id).toList())
        .deepEquals(<String>['second', 'first']);
  });

  test('keeps only the most recent runs', () async {
    for (var i = 0; i < AgentRunRepository.limit + 5; i++) {
      await repository.add(runOf('r$i'));
    }

    final runs = await repository.load();

    // A trace is a few kilobytes, and the storage is the user's.
    check(runs).length.equals(AgentRunRepository.limit);
    check(runs.first.id).equals('r${AgentRunRepository.limit + 4}');
  });

  test('finds the last run of one agent', () async {
    await repository.add(runOf('old', agentId: 'web_answer'));
    await repository.add(runOf('other', agentId: 'price_comparison'));
    await repository.add(runOf('new', agentId: 'web_answer'));

    check((await repository.lastRunOf('web_answer'))?.id).equals('new');
    check((await repository.lastRunOf('price_comparison'))?.id).equals('other');
  });

  test('an agent that never ran has no last run', () async {
    await repository.add(runOf('r1'));

    // Which is what puts `never run` on a card.
    check(await repository.lastRunOf('tool_stress_test')).isNull();
  });

  test('a failed run is kept, with its reason', () async {
    await repository.add(
      runOf('failed', output: '', error: 'Needs Tavily key'),
    );

    final stored = (await repository.load()).single;

    check(stored.succeeded).isFalse();
    check(stored.summary).equals('Needs Tavily key');
  });

  test('shares its file without dropping another repository keys', () async {
    final store = JsonFileStore(directory: root, fileName: 'agent_runs.json');
    await store.write(<String, dynamic>{'something_else': 1});

    await repository.add(runOf('r1'));

    check((await store.read())?['something_else']).equals(1);
  });
}
