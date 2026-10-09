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
  const Agent({
    required this.template,
    required this.isBuiltIn,
    this.isEdited = false,
  });

  final AgentTemplate template;

  /// Whether a version of this agent ships in the bundle.
  ///
  /// Stays true once the user has edited one, because the bundled file is
  /// still there — which is what makes [isEdited] reversible, and what keeps
  /// an edited built-in under `Built-in` on the bench rather than having it
  /// jump to `My agents`. It is also what stops it being deleted: there is no
  /// file on the device to remove, only an override.
  final bool isBuiltIn;

  /// Whether what loaded came from the user's own file rather than the bundle.
  ///
  /// Only ever true alongside [isBuiltIn] — an agent the user built from
  /// scratch is not an edit of anything.
  final bool isEdited;

  /// Whether the shipped version can be put back.
  bool get canReset => isBuiltIn && isEdited;

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
  /// A custom agent whose id matches a built-in wins, so editing a built-in
  /// is a matter of saving a file over its id. One that does is still reported
  /// as built-in, carrying [Agent.isEdited] — it belongs in the same group on
  /// the bench, and its shipped version is still there to go back to.
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
      // Edits of built-ins sort with the built-ins, not above them.
      for (final agent in custom)
        if (!agent.isBuiltIn) agent,
      for (final template in bundled)
        if (customIds.contains(template.id))
          custom.firstWhere((agent) => agent.id == template.id)
        else
          Agent(template: template, isBuiltIn: true),
    ];
  }

  /// The ids that ship in the bundle, which is what makes an edit resettable.
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

  /// Removes the file written for [id].
  ///
  /// For an agent the user built, that is a deletion. For an edited built-in
  /// it is a reset: the bundle's copy cannot be touched, so dropping the
  /// override is what brings the shipped version back.
  Future<void> delete(String id) => _store.delete(id);
}
