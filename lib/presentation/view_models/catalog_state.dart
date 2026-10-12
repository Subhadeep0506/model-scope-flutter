import '../../data/models/catalog_model.dart';

class CatalogState {
  const CatalogState({
    this.models = const <CatalogModel>[],
    this.query = '',
    this.capability,
  });

  final List<CatalogModel> models;
  final String query;
  final ModelCapability? capability;

  List<CatalogModel> get visible {
    final capability = this.capability;
    return <CatalogModel>[
      for (final model in models)
        if (model.matches(query) &&
            (capability == null || model.has(capability)))
          model,
    ];
  }

  String get resultsLabel {
    final count = visible.length;
    return count == 1 ? '1 result' : '$count results';
  }

  String get overline {
    final count = models.length;
    return '${count == 1 ? '1 REPOSITORY' : '$count REPOSITORIES'} · GGUF';
  }

  CatalogState copyWith({
    List<CatalogModel>? models,
    String? query,
    ModelCapability? capability,
    bool clearCapability = false,
  }) => CatalogState(
    models: models ?? this.models,
    query: query ?? this.query,
    capability: clearCapability ? null : (capability ?? this.capability),
  );
}
