import 'dart:developer' as developer;

import '../models/agent_template.dart';
import '../sources/agent_asset_source.dart';
import '../sources/agent_file_store.dart';

/// One agent and where it came from.
///
/// Nothing in the template file says whether it is built in — the same JSON
/// works in the bundle or in the documents directory, which is what lets a
/// custom agent be exported and a built-in one be copied and edited. The
/// origin is known from where it was loaded, and lives here rather than on
/// [AgentTemplate] so the model stays a plain description of the file.
class Agent {
  const Agent({required this.template, required this.isBuiltIn});

  final AgentTemplate template;

  /// Built-ins cannot be edited or deleted; a copy of one can.
  final bool isBuiltIn;

  String get id => template.id;
}

/// Every agent the app can run: the ones shipped in the bundle, and the ones
/// the user built.
class AgentRepository {
  AgentRepository(this._assets, this._store);

  final AgentAssetSource _assets;
  final AgentFileStore _store;

  static const String _logName = 'AgentRepository';

  /// Custom agents first, then built-ins — the order the Agent bench draws
  /// them, with `My agents` above `Built-in`.
  ///
  /// A custom agent whose id matches a built-in wins, so a user can copy one,
  /// change it and have their version be the one that runs.
  Future<List<Agent>> load() async {
    final custom = await _loadCustom();
    final customIds = <String>{for (final agent in custom) agent.id};

    return <Agent>[
      ...custom,
      for (final template in await _assets.load())
        if (!customIds.contains(template.id))
          Agent(template: template, isBuiltIn: true),
    ];
  }

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
        // Unlike a bundled template, which throws, a custom one is skipped:
        // it was written by the user or by an older build, and one bad file
        // must not cost them the rest of their agents.
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

  /// Writes a custom agent, replacing one with the same id. Returns whether it
  /// was saved.
  Future<bool> save(AgentTemplate template) =>
      _store.write(template.id, template.toJson());

  /// Removes a custom agent. A built-in is untouched — it lives in the bundle,
  /// where nothing can delete it.
  Future<void> delete(String id) => _store.delete(id);
}
