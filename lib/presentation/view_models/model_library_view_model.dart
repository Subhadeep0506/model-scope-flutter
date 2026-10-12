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
  Future<void> install(ModelDescriptor model) async {
    final library = await future;
    final models = <ModelDescriptor>[
      for (final existing in library.models)
        if (existing.id != model.id) existing,
      model,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    await _commit(
      library.copyWith(
        models: models,
        activeId: library.activeId ?? (model.isEmbedding ? null : model.id),
      ),
    );
  }

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
    await ref.read(llmServiceProvider).dispose();
  }

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
    final nextActive = <ModelDescriptor>[
      for (final existing in remaining)
        if (!existing.isEmbedding) existing,
    ];
    await _commit(
      ModelLibrary(
        models: remaining,
        projectors: <ProjectorDescriptor>[
          for (final existing in library.projectors)
            if (existing.repoId != projector?.repoId) existing,
        ],
        activeId: wasActive
            ? (nextActive.isEmpty ? null : nextActive.first.id)
            : library.activeId,
      ),
    );
    if (wasActive || projector != null) {
      await ref.read(llmServiceProvider).dispose();
    }
  }

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
    final model = library.byId(id);
    if (library.activeId == id || model == null || model.isEmbedding) return;
    await _commit(library.copyWith(activeId: id));
    await ref.read(llmServiceProvider).dispose();
  }

  bool isInstalled(String id) => current.byId(id) != null;
  ModelLibrary get current => state.value ?? ModelLibrary.empty;

  Future<void> _commit(ModelLibrary library) async {
    state = AsyncData<ModelLibrary>(library);
    await ref.read(modelLibraryRepositoryProvider).save(library);
  }
}
