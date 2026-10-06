import 'dart:developer' as developer;

import '../models/agent_run.dart';
import '../sources/json_file_store.dart';

/// Every agent run the app remembers, newest first.
///
/// One file for all agents rather than one per agent: the Agent bench's RUNS
/// and AVG RUN tiles are totals across every agent, and a card's `last run 6d
/// ago` is one lookup into the same list.
class AgentRunRepository {
  const AgentRunRepository(this._store);

  final JsonFileStore _store;

  /// How many runs are kept. A trace is a few kilobytes and the history card
  /// only ever shows the recent ones, so the file is capped rather than grown
  /// without limit on a device where storage is the user's.
  static const int limit = 50;

  static const String _key = 'runs';

  Future<List<AgentRun>> load() async {
    final document = await _store.read();
    final stored = document?[_key];
    if (stored is! List) return const <AgentRun>[];

    final runs = <AgentRun>[];
    for (final entry in stored) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        runs.add(AgentRun.fromJson(entry));
      } catch (error) {
        // A run written by an older build is dropped rather than throwing:
        // history is a convenience, and losing one row beats losing the app.
        developer.log('Skipped an unreadable run', name: 'AgentRunRepository');
      }
    }
    return runs;
  }

  /// Adds [run] to the front and writes the list back, trimmed to [limit].
  Future<void> add(AgentRun run) async {
    final runs = <AgentRun>[run, ...await load()];
    await save(runs.length > limit ? runs.sublist(0, limit) : runs);
  }

  Future<void> save(List<AgentRun> runs) => _store.merge(<String, dynamic>{
    _key: <Map<String, dynamic>>[for (final run in runs) run.toJson()],
  });

  /// The most recent run of [agentId], or null when it has never run — which
  /// is what puts `never run` on a card.
  Future<AgentRun?> lastRunOf(String agentId) async {
    for (final run in await load()) {
      if (run.agentId == agentId) return run;
    }
    return null;
  }
}
