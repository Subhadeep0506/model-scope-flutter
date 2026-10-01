import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/local_model_library_repository.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

import '../support/fakes.dart';

void main() {
  // `JsonFileStore` encodes and decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late LocalModelLibraryRepository repository;

  /// Creates a stand-in for downloaded weights and returns a model pointing
  /// at it. The weights live outside the app's directory in production, which
  /// is exactly why `load` re-checks them.
  Future<ModelDescriptor> installed({
    String fileName = 'smollm2-360m-instruct-q8_0.gguf',
    bool onDisk = true,
  }) async {
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    if (onDisk) await File(path).writeAsString('weights');
    return fakeInstalledModel(fileName: fileName, localPath: path);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_scope_library');
    repository = LocalModelLibraryRepository(
      JsonFileStore(directory: directory, fileName: 'models.json'),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('an unwritten library loads as empty', () async {
    // Act
    final library = await repository.load();

    // Assert
    check(library.models).isEmpty();
    check(library.activeId).isNull();
  });

  test('a saved library survives a round trip', () async {
    // Arrange
    final model = await installed();

    // Act
    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[model], activeId: model.id),
    );
    final library = await repository.load();

    // Assert — every field the loader needs comes back intact.
    final stored = library.models.single;
    check(stored.id).equals(model.id);
    check(stored.localPath).equals(model.localPath);
    check(stored.quantization).equals('Q8_0');
    check(stored.sizeBytes).equals(model.sizeBytes);
    check(stored.installedAt).equals(model.installedAt);
    check(library.activeId).equals(model.id);
  });

  test('a model whose weights are gone is dropped on load', () async {
    // Arrange — the OS cleared the download cache behind the app's back.
    final present = await installed();
    final missing = await installed(
      fileName: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      onDisk: false,
    );
    await repository.save(
      ModelLibrary(
        models: <ModelDescriptor>[present, missing],
        activeId: present.id,
      ),
    );

    // Act
    final library = await repository.load();

    // Assert — a dangling path would fail inside the native loader instead.
    check(library.models.map((m) => m.id)).deepEquals(<String>[present.id]);
  });

  test('the repair is written back, not recomputed every launch', () async {
    // Arrange
    final present = await installed();
    final missing = await installed(fileName: 'gone.gguf', onDisk: false);
    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[present, missing]),
    );

    // Act
    await repository.load();
    final document = await JsonFileStore(
      directory: directory,
      fileName: 'models.json',
    ).read();

    // Assert
    check(document?['models']).isA<List<dynamic>>().length.equals(1);
  });

  test('an active id pointing at a removed model moves to one that '
      'remains', () async {
    // Arrange
    final present = await installed();
    final missing = await installed(fileName: 'gone.gguf', onDisk: false);
    await repository.save(
      ModelLibrary(
        models: <ModelDescriptor>[present, missing],
        activeId: missing.id,
      ),
    );

    // Act
    final library = await repository.load();

    // Assert — Chat must never open pointing at nothing when a model is there.
    check(library.activeId).equals(present.id);
    check(library.active).isNotNull();
  });

  test('the active id is cleared when nothing is left', () async {
    // Arrange
    final missing = await installed(onDisk: false);
    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[missing], activeId: missing.id),
    );

    // Act
    final library = await repository.load();

    // Assert
    check(library.models).isEmpty();
    check(library.activeId).isNull();
  });

  test('one unreadable record does not hide the rest', () async {
    // Arrange — a record written by an older build, missing a required field.
    final model = await installed();
    await File('${directory.path}${Platform.pathSeparator}models.json')
        .writeAsString(
          jsonEncode(<String, dynamic>{
            'models': <dynamic>[
              <String, dynamic>{'repo_id': 'a/b'},
              model.toJson(),
            ],
            'active_id': null,
          }),
        );

    // Act
    final library = await repository.load();

    // Assert
    check(library.models.map((m) => m.id)).deepEquals(<String>[model.id]);
  });
}
