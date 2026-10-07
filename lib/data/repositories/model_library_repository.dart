import 'dart:developer' as developer;
import 'dart:io';

import '../models/model_descriptor.dart';
import '../models/projector_descriptor.dart';
import '../sources/json_file_store.dart';

class ModelLibrary {
  const ModelLibrary({
    this.models = const <ModelDescriptor>[],
    this.projectors = const <ProjectorDescriptor>[],
    this.activeId,
  });

  static const ModelLibrary empty = ModelLibrary();

  /// Everything installed, embedding models included — which is what the
  /// Settings list and the storage figure want. Anything offering a model to
  /// answer with wants [chatModels] instead.
  final List<ModelDescriptor> models;

  /// Installed vision projectors, at most one per repository.
  final List<ProjectorDescriptor> projectors;

  /// Id of the model Chat loads. Null when nothing is installed.
  final String? activeId;
  bool get isEmpty => models.isEmpty;

  /// Models that can answer a question. An embedding model cannot — it turns
  /// text into vectors — so offering one in a picker would let the user
  /// select a model that is certain to fail.
  List<ModelDescriptor> get chatModels => <ModelDescriptor>[
    for (final model in models)
      if (!model.isEmbedding) model,
  ];

  /// Models that can encode text for the document index.
  List<ModelDescriptor> get embeddingModels => <ModelDescriptor>[
    for (final model in models)
      if (model.isEmbedding) model,
  ];

  /// The embedding model the document index uses, or null when none is
  /// installed. The first, since nothing yet lets the user choose between
  /// two — they are interchangeable at the same vector width.
  ModelDescriptor? get embeddingModel =>
      embeddingModels.isEmpty ? null : embeddingModels.first;

  /// Total bytes on disk, behind the `Models · 8.06 GB` heading. Projectors
  /// count: they are downloaded here and deleted here, so hiding them would
  /// leave the figure short of what the app actually occupies.
  int get totalBytes =>
      models.fold(0, (sum, model) => sum + model.sizeBytes) +
      projectors.fold(0, (sum, projector) => sum + projector.sizeBytes);

  ModelDescriptor? get active => byId(activeId);

  ModelDescriptor? byId(String? id) {
    if (id == null) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// The projector serving [repoId], or null when that repository has none.
  ProjectorDescriptor? projectorFor(String repoId) {
    for (final projector in projectors) {
      if (projector.repoId == repoId) return projector;
    }
    return null;
  }

  /// Whether [model] can read images — that is, whether its repository has a
  /// projector installed.
  bool hasVision(ModelDescriptor model) => projectorFor(model.repoId) != null;

  /// Models still installed from [repoId], excluding [exceptId]. Tells the
  /// remove dialog whether deleting a projector would cost another model its
  /// vision.
  List<ModelDescriptor> modelsOf(String repoId, {String? exceptId}) =>
      <ModelDescriptor>[
        for (final model in models)
          if (model.repoId == repoId && model.id != exceptId) model,
      ];

  ModelLibrary copyWith({
    List<ModelDescriptor>? models,
    List<ProjectorDescriptor>? projectors,
    String? activeId,
  }) => ModelLibrary(
    models: models ?? this.models,
    projectors: projectors ?? this.projectors,
    activeId: activeId ?? this.activeId,
  );
}

class ModelLibraryRepository {
  const ModelLibraryRepository(this._store);

  final JsonFileStore _store;

  static const String _modelsKey = 'models';
  static const String _projectorsKey = 'projectors';
  static const String _activeKey = 'active_id';
  static const String _logName = 'ModelLibraryRepository';

  Future<ModelLibrary> load() async {
    final document = await _store.read();
    if (document == null) return ModelLibrary.empty;

    final stored = _parse(document[_modelsKey]);
    final present = <ModelDescriptor>[];
    for (final model in stored) {
      if (await _isUsable(model.id, model.localPath, model.sizeBytes)) {
        present.add(model);
      }
    }

    // A document written before vision support has no projectors key, which
    // reads as none installed — exactly right, so there is nothing to migrate.
    final storedProjectors = _parseProjectors(document[_projectorsKey]);
    final projectors = <ProjectorDescriptor>[];
    for (final projector in storedProjectors) {
      if (await _isUsable(
        projector.id,
        projector.localPath,
        projector.sizeBytes,
      )) {
        projectors.add(projector);
      }
    }

    final activeId = document[_activeKey];
    final library = ModelLibrary(
      models: present,
      projectors: projectors,
      activeId: activeId is String ? activeId : null,
    );
    final dropped =
        present.length != stored.length ||
        projectors.length != storedProjectors.length;

    // Keep the active id honest when the model behind it vanished.
    if (library.active != null || library.activeId == null) {
      if (dropped) await save(library);
      return library;
    }
    // Built rather than copied: copyWith reads a null activeId as "keep", and
    // clearing it is exactly what an empty library needs. The replacement is
    // drawn from the chat models — an embedding model cannot answer, so
    // falling back to one would make Chat fail on every message.
    final chat = library.chatModels;
    final repaired = ModelLibrary(
      models: present,
      projectors: projectors,
      activeId: chat.isEmpty ? null : chat.first.id,
    );
    await save(repaired);
    return repaired;
  }

  Future<void> save(ModelLibrary library) => _store.write(<String, dynamic>{
    _modelsKey: <Map<String, dynamic>>[
      for (final model in library.models) model.toJson(),
    ],
    _projectorsKey: <Map<String, dynamic>>[
      for (final projector in library.projectors) projector.toJson(),
    ],
    _activeKey: library.activeId,
  });

  /// Whether the file behind a record is still there and still whole. Shared
  /// by models and projectors, which fail the same two ways.
  Future<bool> _isUsable(String id, String localPath, int sizeBytes) async {
    final file = File(localPath);
    if (!await file.exists()) {
      developer.log('Dropping $id: $localPath is gone', name: _logName);
      return false;
    }

    final length = await file.length();
    // Only a *short* file is rejected; a longer one is odd but readable.
    if (length < sizeBytes) {
      developer.log(
        'Dropping $id: $length of $sizeBytes bytes on disk',
        name: _logName,
      );
      return false;
    }
    return true;
  }

  static List<ModelDescriptor> _parse(Object? raw) =>
      _decode(raw, ModelDescriptor.fromJson, 'model');

  static List<ProjectorDescriptor> _parseProjectors(Object? raw) =>
      _decode(raw, ProjectorDescriptor.fromJson, 'projector');

  /// Decodes a stored list, skipping entries that will not read. One
  /// unreadable record should not hide the rest of the library.
  static List<T> _decode<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) read,
    String label,
  ) {
    if (raw is! List) return <T>[];
    final decoded = <T>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        decoded.add(read(entry));
      } catch (error, stackTrace) {
        developer.log(
          'Skipping an unreadable $label record',
          name: _logName,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return decoded;
  }
}
