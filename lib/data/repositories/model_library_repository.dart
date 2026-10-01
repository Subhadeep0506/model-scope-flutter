import '../models/model_descriptor.dart';

/// The installed models and which one Chat answers with.
class ModelLibrary {
  const ModelLibrary({this.models = const <ModelDescriptor>[], this.activeId});

  static const ModelLibrary empty = ModelLibrary();

  final List<ModelDescriptor> models;

  /// Id of the model Chat loads. Null when nothing is installed.
  final String? activeId;

  bool get isEmpty => models.isEmpty;

  /// Total bytes on disk, behind the `Models · 8.06 GB` heading.
  int get totalBytes => models.fold(0, (sum, model) => sum + model.sizeBytes);

  ModelDescriptor? get active => byId(activeId);

  ModelDescriptor? byId(String? id) {
    if (id == null) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  ModelLibrary copyWith({List<ModelDescriptor>? models, String? activeId}) =>
      ModelLibrary(
        models: models ?? this.models,
        activeId: activeId ?? this.activeId,
      );
}

/// Storage for the installed-model registry.
abstract interface class ModelLibraryRepository {
  Future<ModelLibrary> load();

  Future<void> save(ModelLibrary library);
}
