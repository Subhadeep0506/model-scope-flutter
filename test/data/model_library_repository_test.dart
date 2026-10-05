import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/data/sources/json_file_store.dart';

import '../support/fakes.dart';

void main() {
  // `JsonFileStore` encodes and decodes on `compute`, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late ModelLibraryRepository repository;

  /// Stands in for the bytes of a downloaded model. ASCII, so its character
  /// count is also its length on disk.
  const weights = 'GGUF-pretend-weights';

  /// Creates a stand-in for downloaded weights and returns a model pointing at
  /// it. The recorded `sizeBytes` matches what is written, so an ordinary model
  /// reads as whole; [truncated] writes fewer bytes than recorded, standing in
  /// for a download that was cut off.
  Future<ModelDescriptor> installed({
    String fileName = 'smollm2-360m-instruct-q8_0.gguf',
    bool onDisk = true,
    bool truncated = false,
  }) async {
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    if (onDisk) {
      await File(path)
          .writeAsString(truncated ? weights.substring(0, 4) : weights);
    }
    return fakeInstalledModel(
      fileName: fileName,
      localPath: path,
      sizeBytes: weights.length,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_scope_library');
    repository = ModelLibraryRepository(
      JsonFileStore(directory: directory, fileName: 'models.json'),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('an unwritten library loads as empty', () async {
    final library = await repository.load();

    check(library.models).isEmpty();
    check(library.activeId).isNull();
  });

  test('a saved library survives a round trip', () async {
    final model = await installed();

    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[model], activeId: model.id),
    );
    final library = await repository.load();

    // Every field the loader needs comes back intact.
    final stored = library.models.single;
    check(stored.id).equals(model.id);
    check(stored.localPath).equals(model.localPath);
    check(stored.quantization).equals('Q8_0');
    check(stored.sizeBytes).equals(model.sizeBytes);
    check(stored.installedAt).equals(model.installedAt);
    check(library.activeId).equals(model.id);
  });

  test('a model whose weights are gone is dropped on load', () async {
    // The OS cleared the download cache behind the app's back.
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

    final library = await repository.load();

    // A dangling path would fail inside the native loader instead.
    check(library.models.map((m) => m.id)).deepEquals(<String>[present.id]);
  });

  test('a model shorter than its recorded size is dropped on load', () async {
    // A transfer that died part-way leaves a file that exists and
    // cannot be read, which fails much later inside the native loader.
    final whole = await installed();
    final partial = await installed(
      fileName: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      truncated: true,
    );
    await repository.save(
      ModelLibrary(
        models: <ModelDescriptor>[whole, partial],
        activeId: whole.id,
      ),
    );

    final library = await repository.load();

    check(library.models.map((m) => m.id)).deepEquals(<String>[whole.id]);
  });

  test('an active id pointing at a partial download is repaired', () async {
    final whole = await installed();
    final partial = await installed(
      fileName: 'cut-short.gguf',
      truncated: true,
    );
    await repository.save(
      ModelLibrary(
        models: <ModelDescriptor>[whole, partial],
        activeId: partial.id,
      ),
    );

    final library = await repository.load();

    // Chat opens on something it can actually load.
    check(library.activeId).equals(whole.id);
  });

  test('the repair is written back, not recomputed every launch', () async {
    final present = await installed();
    final missing = await installed(fileName: 'gone.gguf', onDisk: false);
    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[present, missing]),
    );

    await repository.load();
    final document = await JsonFileStore(
      directory: directory,
      fileName: 'models.json',
    ).read();

    check(document?['models']).isA<List<dynamic>>().length.equals(1);
  });

  test('an active id pointing at a removed model moves to one that '
      'remains', () async {
    final present = await installed();
    final missing = await installed(fileName: 'gone.gguf', onDisk: false);
    await repository.save(
      ModelLibrary(
        models: <ModelDescriptor>[present, missing],
        activeId: missing.id,
      ),
    );

    final library = await repository.load();

    // Chat must never open pointing at nothing when a model is there.
    check(library.activeId).equals(present.id);
    check(library.active).isNotNull();
  });

  test('the active id is cleared when nothing is left', () async {
    final missing = await installed(onDisk: false);
    await repository.save(
      ModelLibrary(models: <ModelDescriptor>[missing], activeId: missing.id),
    );

    final library = await repository.load();

    check(library.models).isEmpty();
    check(library.activeId).isNull();
  });

  test('one unreadable record does not hide the rest', () async {
    // A record written by an older build, missing a required field.
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

    final library = await repository.load();

    check(library.models.map((m) => m.id)).deepEquals(<String>[model.id]);
  });

  group('projectors', () {
    /// A projector on disk for [repoId], sized to what is written.
    Future<ProjectorDescriptor> projector({
      String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
      String fileName = 'mmproj-BF16.gguf',
      bool onDisk = true,
    }) async {
      final path = '${directory.path}${Platform.pathSeparator}$fileName';
      if (onDisk) await File(path).writeAsString(weights);
      return fakeProjector(
        repoId: repoId,
        fileName: fileName,
        localPath: path,
        sizeBytes: weights.length,
      );
    }

    test('a projector survives a save and load', () async {
      final model = await installed();
      final mmproj = await projector();
      await repository.save(
        ModelLibrary(
          models: <ModelDescriptor>[model],
          projectors: <ProjectorDescriptor>[mmproj],
          activeId: model.id,
        ),
      );

      final library = await repository.load();

      check(library.projectorFor(model.repoId)?.fileName)
          .equals('mmproj-BF16.gguf');
      check(library.hasVision(model)).isTrue();
    });

    test('a library written before vision loads with none', () async {
      // No `projectors` key at all, which is every document the app wrote
      // before this feature existed.
      final model = await installed();
      await File('${directory.path}${Platform.pathSeparator}models.json')
          .writeAsString(
            jsonEncode(<String, dynamic>{
              'models': <dynamic>[model.toJson()],
              'active_id': model.id,
            }),
          );

      final library = await repository.load();

      check(library.models).length.equals(1);
      check(library.projectors).isEmpty();
      check(library.hasVision(model)).isFalse();
    });

    test('a projector whose file is gone is dropped', () async {
      final model = await installed();
      final mmproj = await projector(onDisk: false);
      await repository.save(
        ModelLibrary(
          models: <ModelDescriptor>[model],
          projectors: <ProjectorDescriptor>[mmproj],
          activeId: model.id,
        ),
      );

      final library = await repository.load();

      // The model is untouched; only its sight goes.
      check(library.models).length.equals(1);
      check(library.projectors).isEmpty();
    });

    test('a projector belongs to its repository, not to one quant', () async {
      final q8 = await installed();
      final q4 = await installed(fileName: 'smollm2-360m-instruct-q4_k_m.gguf');
      final mmproj = await projector();
      await repository.save(
        ModelLibrary(
          models: <ModelDescriptor>[q8, q4],
          projectors: <ProjectorDescriptor>[mmproj],
          activeId: q8.id,
        ),
      );

      final library = await repository.load();

      check(library.hasVision(q8)).isTrue();
      check(library.hasVision(q4)).isTrue();
    });

    test('a projector from another repository gives no vision', () async {
      final model = await installed();
      final mmproj = await projector(repoId: 'someone/else-GGUF');
      final library = ModelLibrary(
        models: <ModelDescriptor>[model],
        projectors: <ProjectorDescriptor>[mmproj],
      );

      check(library.hasVision(model)).isFalse();
      check(library.projectorFor(model.repoId)).isNull();
    });

    test('projector bytes count toward the total', () async {
      final model = await installed();
      final mmproj = await projector();
      final library = ModelLibrary(
        models: <ModelDescriptor>[model],
        projectors: <ProjectorDescriptor>[mmproj],
      );

      check(library.totalBytes).equals(model.sizeBytes + mmproj.sizeBytes);
    });

    test('modelsOf names the other quants sharing a projector', () async {
      final q8 = await installed();
      final q4 = await installed(fileName: 'smollm2-360m-instruct-q4_k_m.gguf');
      final library = ModelLibrary(models: <ModelDescriptor>[q8, q4]);

      final sharers = library.modelsOf(q8.repoId, exceptId: q8.id);

      check(sharers.map((m) => m.id)).deepEquals(<String>[q4.id]);
    });
  });
}
