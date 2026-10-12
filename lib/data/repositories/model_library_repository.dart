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
  final List<ModelDescriptor> models;
  final List<ProjectorDescriptor> projectors;

  final String? activeId;
  bool get isEmpty => models.isEmpty;

  List<ModelDescriptor> get chatModels => <ModelDescriptor>[
    for (final model in models)
      if (!model.isEmbedding) model,
  ];

  List<ModelDescriptor> get embeddingModels => <ModelDescriptor>[
    for (final model in models)
      if (model.isEmbedding) model,
  ];

  ModelDescriptor? get embeddingModel =>
      embeddingModels.isEmpty ? null : embeddingModels.first;

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

  ProjectorDescriptor? projectorFor(String repoId) {
    for (final projector in projectors) {
      if (projector.repoId == repoId) return projector;
    }
    return null;
  }

  bool hasVision(ModelDescriptor model) => projectorFor(model.repoId) != null;

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

    if (library.active != null || library.activeId == null) {
      if (dropped) await save(library);
      return library;
    }

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

  Future<bool> _isUsable(String id, String localPath, int sizeBytes) async {
    final file = File(localPath);
    if (!await file.exists()) {
      developer.log('Dropping $id: $localPath is gone', name: _logName);
      return false;
    }

    final length = await file.length();

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
