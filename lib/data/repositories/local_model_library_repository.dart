import 'dart:developer' as developer;
import 'dart:io';

import '../models/model_descriptor.dart';
import '../sources/json_file_store.dart';
import 'model_library_repository.dart';

/// [ModelLibraryRepository] backed by `models.json` in the documents directory.
///
/// Weights themselves live in `nobodywho`'s download cache, not in a directory
/// the app owns, so every load re-checks that each recorded file is still
/// there. Without that, clearing storage from the OS settings would leave Chat
/// pointing at a path that no longer exists and failing with a native error.
class LocalModelLibraryRepository implements ModelLibraryRepository {
  const LocalModelLibraryRepository(this._store);

  final JsonFileStore _store;

  static const String _modelsKey = 'models';
  static const String _activeKey = 'active_id';
  static const String _logName = 'LocalModelLibraryRepository';

  @override
  Future<ModelLibrary> load() async {
    final document = await _store.read();
    if (document == null) return ModelLibrary.empty;

    final stored = _parse(document[_modelsKey]);
    final present = <ModelDescriptor>[];
    for (final model in stored) {
      if (await File(model.localPath).exists()) {
        present.add(model);
        continue;
      }
      developer.log(
        'Dropping ${model.id}: ${model.localPath} is gone',
        name: _logName,
      );
    }

    final activeId = document[_activeKey];
    final library = ModelLibrary(
      models: present,
      activeId: activeId is String ? activeId : null,
    );

    // Keep the active id honest when the model behind it vanished.
    if (library.active != null || library.activeId == null) {
      if (present.length != stored.length) await save(library);
      return library;
    }
    final repaired = ModelLibrary(
      models: present,
      activeId: present.isEmpty ? null : present.first.id,
    );
    await save(repaired);
    return repaired;
  }

  @override
  Future<void> save(ModelLibrary library) => _store.write(<String, dynamic>{
    _modelsKey: <Map<String, dynamic>>[
      for (final model in library.models) model.toJson(),
    ],
    _activeKey: library.activeId,
  });

  static List<ModelDescriptor> _parse(Object? raw) {
    if (raw is! List) return const <ModelDescriptor>[];
    final models = <ModelDescriptor>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        models.add(ModelDescriptor.fromJson(entry));
      } catch (error, stackTrace) {
        // One unreadable record should not hide the rest of the library.
        developer.log(
          'Skipping an unreadable model record',
          name: _logName,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return models;
  }
}
