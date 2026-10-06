import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/sources/agent_asset_source.dart';
import 'package:model_scope_flutter/domain/services/agent_validator.dart';
import 'package:model_scope_flutter/domain/tools/tool_registry.dart';

import 'package:model_scope_flutter/domain/services/firecrawl_web_crawler_service.dart';
import 'package:model_scope_flutter/data/sources/firecrawl_api_client.dart';
import 'package:model_scope_flutter/data/sources/tavily_api_client.dart';
import 'package:model_scope_flutter/domain/services/tavily_web_search_service.dart';
import 'package:http/http.dart' as http;

void main() {
  // The source decodes on `compute`, and the shipped-templates test reads real
  // assets — both need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  String templateJson(String id, {String name = 'An agent'}) =>
      jsonEncode(<String, Object?>{
        'id': id,
        'name': name,
        'purpose': 'p',
        'system_prompt': 's',
        'pipeline': <Map<String, Object?>>[],
        'answer': <String, Object?>{'prompt': 'Answer.'},
      });

  /// A bundle holding [files] by path, with the asset manifest the enumerator
  /// reads built from their keys.
  AssetBundle bundleOf(Map<String, String> files) =>
      _FakeBundle(files, files.keys.toList());

  test('finds every template in the directory, in a stable order', () async {
    final source = AgentAssetSource(
      bundle: bundleOf(<String, String>{
        'assets/agents/zebra.json': templateJson('zebra'),
        'assets/agents/alpha.json': templateJson('alpha'),
      }),
    );

    final templates = await source.load();

    // Sorted by file name, so the Agent bench draws them the same way on
    // every launch rather than in whatever order the manifest happened to be.
    check(templates.map((t) => t.id).toList())
        .deepEquals(<String>['alpha', 'zebra']);
  });

  test('ignores anything that is not a template', () async {
    final source = AgentAssetSource(
      bundle: bundleOf(<String, String>{
        'assets/agents/real.json': templateJson('real'),
        'assets/agents/notes.txt': 'not a template',
        'assets/catalog/models.json': '[]',
      }),
    );

    check(await source.load()).length.equals(1);
  });

  test('reads the bundle once however often it is asked', () async {
    final bundle = _FakeBundle(
      <String, String>{'assets/agents/a.json': templateJson('a')},
      <String>['assets/agents/a.json'],
    );
    final source = AgentAssetSource(bundle: bundle);

    await source.load();
    await source.load();

    // The Agent bench rebuilds whenever a run finishes, and the bundled
    // templates cannot change while the app is running.
    check(bundle.reads).equals(1);
  });

  test(
    'a malformed bundled template throws rather than being skipped',
    () async {
      final source = AgentAssetSource(
        bundle: bundleOf(<String, String>{
          'assets/agents/broken.json': '{"id": "broken"}',
        }),
      );

      // These files are authored in this repository, so a bad one is a
      // build-time mistake and should be loud. A custom agent is the opposite
      // case and is skipped instead.
      await check(source.load()).throws<Object>();
    },
  );

  test('a template that is a list, not an object, throws', () async {
    final source = AgentAssetSource(
      bundle: bundleOf(<String, String>{'assets/agents/a.json': '[]'}),
    );

    await check(source.load()).throws<FormatException>();
  });

  test('the templates this build ships parse and validate', () async {
    // The one test that would catch a typo in a real template file.
    final templates = await AgentAssetSource().load();
    final validator = AgentValidator(_realRegistry());

    check(templates).isNotEmpty();
    for (final template in templates) {
      check(
        validator.structuralProblems(template),
        because: '${template.id} must be runnable as shipped',
      ).isEmpty();

      check(template.name, because: template.id).isNotEmpty();
      check(template.purpose, because: template.id).isNotEmpty();
      check(template.systemPrompt, because: template.id).isNotEmpty();
      check(template.pipeline, because: template.id).isNotEmpty();
    }
  });

  test('at least one shipped agent needs no API key', () async {
    final templates = await AgentAssetSource().load();
    const gated = <String>{'web_search', 'read_web_page'};

    final offline = templates.where(
      (template) => template.toolNames.every((tool) => !gated.contains(tool)),
    );

    // A fresh install has no keys. Without one of these the Agent tab is a
    // list of things the user cannot try.
    check(offline).isNotEmpty();
  });
}

/// The registry the app really builds, so the shipped templates are checked
/// against the tools that will actually be there rather than a stand-in. The
/// services never reach the network: nothing here runs a tool.
ToolRegistry _realRegistry() {
  final client = http.Client();
  return ToolRegistry.standard(
    search: TavilyWebSearchService(TavilyApiClient(client), () async => ''),
    crawler: FirecrawlWebCrawlerService(
      FirecrawlApiClient(client),
      () async => '',
    ),
  );
}

/// An [AssetBundle] serving [_files] by path, and an asset manifest listing
/// [_assets]. The manifest is the binary `StandardMessageCodec` map that
/// `AssetManifest.loadFromAssetBundle` expects — a map of asset path to its
/// list of variants, which is empty for everything here.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._files, this._assets);

  final Map<String, String> _files;
  final List<String> _assets;

  /// How many times the source went to the bundle for the manifest.
  int reads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final body = _files[key];
    if (body == null) throw StateError('No asset at $key');
    return body;
  }

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      reads++;
      final message = const StandardMessageCodec().encodeMessage(
        <String, Object?>{for (final asset in _assets) asset: <Object?>[]},
      );
      if (message == null) throw StateError('Could not encode the manifest');
      return message;
    }
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(await loadString(key))),
    );
  }
}
