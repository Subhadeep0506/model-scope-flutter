import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;

import '../models/agent_template.dart';

class AgentAssetSource {
  AgentAssetSource({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String directory = 'assets/agents/';
  final AssetBundle _bundle;

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

AgentTemplate _decodeTemplate(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('An agent template must be a JSON object.');
  }
  return AgentTemplate.fromJson(decoded);
}
