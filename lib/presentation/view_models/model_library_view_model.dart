import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/projector_descriptor.dart';
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
    // Awaited, not `current`: a download finishing while models.json is still
    // being read would otherwise be overwritten by the load.
    final library = await future;
    final models = <ModelDescriptor>[
      for (final existing in library.models)
        if (existing.id != model.id) existing,
      model,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    await _commit(
      library.copyWith(models: models, activeId: library.activeId ?? model.id),
    );
  }

  /// Records a downloaded projector, replacing whatever that repository had
  /// before — a repository has one projector, and the newly fetched file is
  /// the one the user asked for.
  Future<void> installProjector(ProjectorDescriptor projector) async {
    final library = await future;
    final previous = library.projectorFor(projector.repoId);
    if (previous != null && previous.localPath != projector.localPath) {
      await _deleteFile(previous.localPath);
    }

    await _commit(
      library.copyWith(
        projectors: <ProjectorDescriptor>[
          for (final existing in library.projectors)
            if (existing.repoId != projector.repoId) existing,
          projector,
        ],
      ),
    );
    // The model in memory was loaded without sight. Drop it so the next chat
    // open picks the projector up.
    await ref.read(llmServiceProvider).dispose();
  }

  /// Deletes the weights and forgets the model. Unlike Clear cache this is
  /// explicit and one at a time, so the file really does go. [alsoProjector]
  /// takes the repository's projector with it.
  Future<void> remove(String id, {bool alsoProjector = false}) async {
    final library = await future;
    final model = library.byId(id);
    if (model == null) return;

    await _deleteFile(model.localPath);

    final projector = alsoProjector ? library.projectorFor(model.repoId) : null;
    if (projector != null) await _deleteFile(projector.localPath);

    final remaining = <ModelDescriptor>[
      for (final existing in library.models)
        if (existing.id != id) existing,
    ];
    final wasActive = library.activeId == id;
    await _commit(
      ModelLibrary(
        models: remaining,
        projectors: <ProjectorDescriptor>[
          for (final existing in library.projectors)
            if (existing.repoId != projector?.repoId) existing,
        ],
        activeId: wasActive
            ? (remaining.isEmpty ? null : remaining.first.id)
            : library.activeId,
      ),
    );
    if (wasActive || projector != null) {
      await ref.read(llmServiceProvider).dispose();
    }
  }

  /// Deletes a file, keeping the record change going if it will not go. A
  /// locked file would otherwise leave a row that can never be dismissed.
  /// Deleted without checking first: a file that is already gone raises the
  /// same exception as one that will not go, and both end the same way.
  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      developer.log('Could not delete $path', name: _logName, error: error);
    }
  }

  /// Switches the model Chat loads next.
  Future<void> setActive(String id) async {
    final library = await future;
    if (library.activeId == id || library.byId(id) == null) return;
    await _commit(ModelLibrary(models: library.models, activeId: id));
    // Drop the loaded weights so the next chat open picks the new model up.
    await ref.read(llmServiceProvider).dispose();
  }

  bool isInstalled(String id) => current.byId(id) != null;

  ModelLibrary get current => state.value ?? ModelLibrary.empty;

  Future<void> _commit(ModelLibrary library) async {
    state = AsyncData<ModelLibrary>(library);
    await ref.read(modelLibraryRepositoryProvider).save(library);
  }
}
