import 'dart:developer' as developer;

import '../models/agent_run.dart';
import '../sources/json_file_store.dart';

class AgentRunRepository {
  const AgentRunRepository(this._store);
  final JsonFileStore _store;
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
        developer.log('Skipped an unreadable run', name: 'AgentRunRepository');
      }
    }
    return runs;
  }

  Future<void> add(AgentRun run) async {
    final runs = <AgentRun>[run, ...await load()];
    await save(runs.length > limit ? runs.sublist(0, limit) : runs);
  }

  Future<void> save(List<AgentRun> runs) => _store.merge(<String, dynamic>{
    _key: <Map<String, dynamic>>[for (final run in runs) run.toJson()],
  });

  Future<AgentRun?> lastRunOf(String agentId) async {
    for (final run in await load()) {
      if (run.agentId == agentId) return run;
    }
    return null;
  }
}
