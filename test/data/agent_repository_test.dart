import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/data/sources/agent_asset_source.dart';
import 'package:model_scope_flutter/data/sources/agent_file_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent_repository_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Map<String, Object?> templateMap(String id, {String? name}) =>
      <String, Object?>{
        'id': id,
        'name': name ?? id,
        'purpose': 'p',
        'system_prompt': 's',
        'pipeline': <Map<String, Object?>>[],
        'answer': <String, Object?>{'prompt': 'Answer.'},
      };

  AgentRepository repositoryOf(
    Map<String, Map<String, Object?>> bundled,
    AgentFileStore store,
  ) => AgentRepository(
    AgentAssetSource(
      bundle: _FakeBundle(<String, String>{
        for (final entry in bundled.entries)
          'assets/agents/${entry.key}.json': jsonEncode(entry.value),
      }),
    ),
    store,
  );

  test('lists custom agents before built-in ones', () async {
    final store = AgentFileStore(directory: root);
    await store.write('mine', templateMap('mine', name: 'Mine'));
    final repository = repositoryOf(<String, Map<String, Object?>>{
      'shipped': templateMap('shipped', name: 'Shipped'),
    }, store);

    final agents = await repository.load();

    // `My agents` sits above `Built-in` on the Agent bench.
    check(agents.map((agent) => agent.id).toList())
        .deepEquals(<String>['mine', 'shipped']);
    check(agents.first.isBuiltIn).isFalse();
    check(agents.last.isBuiltIn).isTrue();
  });

  test('knows which agents came from the bundle', () async {
    final repository = repositoryOf(<String, Map<String, Object?>>{
      'shipped': templateMap('shipped'),
    }, AgentFileStore(directory: root));

    final agent = await repository.byId('shipped');

    // Nothing in the JSON says so — the same file works in either place, which
    // is what lets a custom agent be exported.
    check(agent?.isBuiltIn).isNotNull().isTrue();
  });

  test('a custom agent sharing an id replaces the built-in', () async {
    final store = AgentFileStore(directory: root);
    await store.write('shipped', templateMap('shipped', name: 'My version'));
    final repository = repositoryOf(<String, Map<String, Object?>>{
      'shipped': templateMap('shipped', name: 'Theirs'),
    }, store);

    final agents = await repository.load();

    // So a user can copy a built-in, change it, and have theirs be the one
    // that runs.
    check(agents).length.equals(1);
    check(agents.single.template.name).equals('My version');
    check(agents.single.isBuiltIn).isFalse();
  });

  test('sorts custom agents by name', () async {
    final store = AgentFileStore(directory: root);
    await store.write('b', templateMap('b', name: 'Zebra'));
    await store.write('a', templateMap('a', name: 'Alpha'));
    final repository = repositoryOf(
      const <String, Map<String, Object?>>{},
      store,
    );

    final agents = await repository.load();

    check(agents.map((agent) => agent.template.name).toList())
        .deepEquals(<String>['Alpha', 'Zebra']);
  });

  test('skips a custom agent that will not parse', () async {
    final store = AgentFileStore(directory: root);
    await store.write('good', templateMap('good'));
    await store.write('bad', <String, dynamic>{'id': 'bad'});
    final repository = repositoryOf(<String, Map<String, Object?>>{
      'shipped': templateMap('shipped'),
    }, store);

    final agents = await repository.load();

    // A file written by an older build must not cost the user the others, nor
    // the built-ins.
    check(agents.map((agent) => agent.id).toList())
        .deepEquals(<String>['good', 'shipped']);
  });

  test('saves a custom agent and finds it again', () async {
    final store = AgentFileStore(directory: root);
    final repository = repositoryOf(
      const <String, Map<String, Object?>>{},
      store,
    );

    check(await repository.save(AgentTemplate.fromJson(templateMap('new_one'))))
        .isTrue();

    check((await repository.byId('new_one'))?.isBuiltIn).isNotNull().isFalse();
  });

  test('deletes a custom agent', () async {
    final store = AgentFileStore(directory: root);
    await store.write('mine', templateMap('mine'));
    final repository = repositoryOf(
      const <String, Map<String, Object?>>{},
      store,
    );

    await repository.delete('mine');

    check(await repository.load()).isEmpty();
  });

  test('deleting cannot remove a built-in', () async {
    final store = AgentFileStore(directory: root);
    final repository = repositoryOf(<String, Map<String, Object?>>{
      'shipped': templateMap('shipped'),
    }, store);

    await repository.delete('shipped');

    // It lives in the bundle, where nothing the app does can reach it.
    check(await repository.byId('shipped')).isNotNull();
  });

  test('answers null for an agent that is not there', () async {
    final repository = repositoryOf(
      const <String, Map<String, Object?>>{},
      AgentFileStore(directory: root),
    );

    check(await repository.byId('nobody')).isNull();
  });
}

/// An [AssetBundle] serving [_files], with a manifest built from their keys.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._files);

  final Map<String, String> _files;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final body = _files[key];
    if (body == null) throw StateError('No asset at $key');
    return body;
  }

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final message = const StandardMessageCodec().encodeMessage(
        <String, Object?>{for (final path in _files.keys) path: <Object?>[]},
      );
      if (message == null) throw StateError('Could not encode the manifest');
      return message;
    }
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(await loadString(key))),
    );
  }
}
