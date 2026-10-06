import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;

import '../models/agent_template.dart';

/// The agents this build ships, one JSON file each under `assets/agents/`.
///
/// The directory is enumerated rather than indexed: adding an agent is
/// dropping in a file, with no list to keep in step. The order is the file
/// names sorted, so the Agent bench draws them the same way every launch.
class AgentAssetSource {
  AgentAssetSource({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String directory = 'assets/agents/';

  final AssetBundle _bundle;

  /// Decoded once and held: the bundled templates cannot change while the app
  /// runs, and the Agent bench rebuilds whenever a run finishes.
  Future<List<AgentTemplate>>? _cached;

  Future<List<AgentTemplate>> load() => _cached ??= _read();

  Future<List<AgentTemplate>> _read() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    final paths =
        manifest
            .listAssets()
            .where(
              (path) => path.startsWith(directory) && path.endsWith('.json'),
            )
            .toList()
          ..sort();

    final templates = <AgentTemplate>[];
    for (final path in paths) {
      templates.add(
        await compute(_decodeTemplate, await _bundle.loadString(path)),
      );
    }
    return templates;
  }
}

/// A malformed bundled template throws rather than being skipped. The file is
/// authored in this repository, so a bad one is a build-time mistake that
/// should be loud — the same rule the model catalog follows. A *custom*
/// template is the opposite case and is skipped, because the user can have
/// written anything.
AgentTemplate _decodeTemplate(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('An agent template must be a JSON object.');
  }
  return AgentTemplate.fromJson(decoded);
}
