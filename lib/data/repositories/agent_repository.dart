import 'dart:developer' as developer;

import '../models/agent_template.dart';
import '../sources/agent_asset_source.dart';
import '../sources/agent_file_store.dart';

class Agent {
  const Agent({
    required this.template,
    required this.isBuiltIn,
    this.isEdited = false,
  });
  final AgentTemplate template;
  final bool isBuiltIn;
  final bool isEdited;
  bool get canReset => isBuiltIn && isEdited;

  String get id => template.id;
}

class AgentRepository {
  AgentRepository(this._assets, this._store);

  final AgentAssetSource _assets;
  final AgentFileStore _store;

  static const String _logName = 'AgentRepository';

  Future<List<Agent>> load() async {
    final bundled = await _assets.load();
    final bundledIds = <String>{for (final template in bundled) template.id};
    final custom = <Agent>[
      for (final agent in await _loadCustom())
        if (bundledIds.contains(agent.id))
          Agent(template: agent.template, isBuiltIn: true, isEdited: true)
        else
          agent,
    ];
    final customIds = <String>{for (final agent in custom) agent.id};

    return <Agent>[
      for (final agent in custom)
        if (!agent.isBuiltIn) agent,
      for (final template in bundled)
        if (customIds.contains(template.id))
          custom.firstWhere((agent) => agent.id == template.id)
        else
          Agent(template: template, isBuiltIn: true),
    ];
  }

  Future<Set<String>> builtInIds() async => <String>{
    for (final template in await _assets.load()) template.id,
  };

  Future<List<Agent>> _loadCustom() async {
    final documents = await _store.readAll();
    final agents = <Agent>[];

    for (final entry in documents.entries) {
      try {
        agents.add(
          Agent(
            template: AgentTemplate.fromJson(entry.value),
            isBuiltIn: false,
          ),
        );
      } catch (error, stackTrace) {
        developer.log(
          'Skipped custom agent ${entry.key}',
          name: _logName,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    agents.sort((a, b) => a.template.name.compareTo(b.template.name));
    return agents;
  }

  Future<Agent?> byId(String id) async {
    for (final agent in await load()) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  Future<bool> save(AgentTemplate template) =>
      _store.write(template.id, template.toJson());

  Future<void> delete(String id) => _store.delete(id);
}
