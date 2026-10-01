import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/model_library_repository.dart';

/// Owns the installed models and which one Chat answers with.
class ModelLibraryViewModel extends AsyncNotifier<ModelLibrary> {
  static const String _logName = 'ModelLibraryViewModel';

  @override
  Future<ModelLibrary> build() =>
      ref.read(modelLibraryRepositoryProvider).load();

  /// Records a freshly downloaded model, making it active when it is the only
  /// one — so the first download is usable in Chat without a second tap.
  Future<void> install(ModelDescriptor model) async {
    // Awaiting the build rather than reading `current`: a download that
    // finishes while models.json is still being read would otherwise be
    // written into an empty library and then overwritten by the load.
    final library = await future;
    final models = <ModelDescriptor>[
      for (final existing in library.models)
        if (existing.id != model.id) existing,
      model,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    await _commit(
      ModelLibrary(models: models, activeId: library.activeId ?? model.id),
    );
  }

  /// Deletes the weights and forgets the model.
  ///
  /// Unlike Clear cache, this is the explicit, one-at-a-time way to free the
  /// gigabytes a model occupies, so the file really does go.
  Future<void> remove(String id) async {
    final library = await future;
    final model = library.byId(id);
    if (model == null) return;

    try {
      final file = File(model.localPath);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      // The record still goes, otherwise a locked file leaves a row that can
      // never be dismissed.
      developer.log(
        'Could not delete ${model.localPath}',
        name: _logName,
        error: error,
      );
    }

    final remaining = <ModelDescriptor>[
      for (final existing in library.models)
        if (existing.id != id) existing,
    ];
    final wasActive = library.activeId == id;
    await _commit(
      ModelLibrary(
        models: remaining,
        activeId: wasActive
            ? (remaining.isEmpty ? null : remaining.first.id)
            : library.activeId,
      ),
    );
    if (wasActive) await ref.read(llmServiceProvider).dispose();
  }

  /// Switches the model Chat loads next.
  Future<void> setActive(String id) async {
    final library = await future;
    if (library.activeId == id || library.byId(id) == null) return;
    await _commit(ModelLibrary(models: library.models, activeId: id));
    // Drop the loaded weights so the next chat open picks the new model up.
    await ref.read(llmServiceProvider).dispose();
  }

  /// Whether [id] names a model that is already on disk.
  bool isInstalled(String id) => current.byId(id) != null;

  ModelLibrary get current => state.value ?? ModelLibrary.empty;

  Future<void> _commit(ModelLibrary library) async {
    state = AsyncData<ModelLibrary>(library);
    await ref.read(modelLibraryRepositoryProvider).save(library);
  }
}
