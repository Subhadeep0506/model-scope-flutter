import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/repositories/catalog_repository.dart';

void main() {
  // The repository decodes on `compute`, and the shipped-manifest test reads a
  // real asset — both need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// An [AssetBundle] serving [body] for every key, counting the reads. The
  /// catalog rebuilds on every keystroke, so the read count matters.
  late int reads;

  AssetBundle bundleOf(String body) {
    reads = 0;
    return _FakeBundle((_) async {
      reads++;
      return body;
    });
  }

  String manifest(List<Map<String, Object?>> entries) => jsonEncode(entries);

  test('decodes an entry into the fields the card draws', () async {
    final repository = CatalogRepository(
      bundle: bundleOf(
        manifest(<Map<String, Object?>>[
          <String, Object?>{
            'repo_id': 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
            'name': 'Qwen2.5 Coder 1.5B Instruct',
            'description': 'Compact code generation model.',
            'param_label': '1.5B',
            'capabilities': <String>['text_to_text', 'tool_calling'],
          },
        ]),
      ),
    );

    final models = await repository.load();

    final model = models.single;
    check(model.repoId).equals('bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF');
    check(model.name).equals('Qwen2.5 Coder 1.5B Instruct');
    check(model.paramLabel).equals('1.5B');
    check(model.author).equals('bartowski');
    check(model.capabilities).deepEquals(<ModelCapability>[
      ModelCapability.textToText,
      ModelCapability.toolCalling,
    ]);
  });

  test('an entry with no capabilities still loads', () async {
    // The key is optional in the manifest.
    final repository = CatalogRepository(
      bundle: bundleOf(
        manifest(<Map<String, Object?>>[
          <String, Object?>{
            'repo_id': 'a/b',
            'name': 'B',
            'description': 'Something.',
          },
        ]),
      ),
    );

    final models = await repository.load();

    check(models.single.capabilities).isEmpty();
    check(models.single.paramLabel).isNull();
  });

  test('keeps the order the manifest was authored in', () async {
    // The file is the running order of the catalog screen.
    final repository = CatalogRepository(
      bundle: bundleOf(
        manifest(<Map<String, Object?>>[
          <String, Object?>{'repo_id': 'a/1', 'name': '1', 'description': ''},
          <String, Object?>{'repo_id': 'a/2', 'name': '2', 'description': ''},
          <String, Object?>{'repo_id': 'a/3', 'name': '3', 'description': ''},
        ]),
      ),
    );

    final models = await repository.load();

    check(models.map((m) => m.repoId))
        .deepEquals(<String>['a/1', 'a/2', 'a/3']);
  });

  test('reads the asset once however often it is asked', () async {
    final repository = CatalogRepository(
      bundle: bundleOf(
        manifest(<Map<String, Object?>>[
          <String, Object?>{'repo_id': 'a/b', 'name': 'B', 'description': ''},
        ]),
      ),
    );

    await repository.load();
    await repository.load();
    await repository.load();

    // The manifest cannot change while the app runs.
    check(reads).equals(1);
  });

  test('a manifest that is not a list is a loud build-time error', () async {
    // Authored in this repository, so a bad one must not be skipped
    // quietly into an empty catalog.
    final repository = CatalogRepository(
      bundle: bundleOf(jsonEncode(<String, Object?>{'repo_id': 'a/b'})),
    );

    await check(repository.load()).throws<FormatException>();
  });

  test('the manifest this build ships actually parses', () async {
    // The one test that would catch a typo in the real file.
    final repository = CatalogRepository();

    final models = await repository.load();

    // Every entry names a repository and says something about itself.
    check(models).isNotEmpty();
    for (final model in models) {
      check(model.repoId, because: model.name).contains('/');
      check(model.description, because: model.name).isNotEmpty();
    }
  });
}

/// An [AssetBundle] backed by a function, so a test can serve a manifest
/// without writing one into the build.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.read);

  final Future<String> Function(String key) read;

  @override
  Future<String> loadString(String key, {bool cache = true}) => read(key);

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(await read(key))));
}
