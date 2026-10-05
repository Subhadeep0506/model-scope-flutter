import '../../data/models/catalog_model.dart';

/// What the Model catalog screen is showing: the whole catalog, with the
/// search text and capability filter applied on read. No paging or cursor —
/// the list ships with the app, so narrowing it is not a request.
class CatalogState {
  const CatalogState({
    this.models = const <CatalogModel>[],
    this.query = '',
    this.capability,
  });

  final List<CatalogModel> models;
  final String query;

  /// The selected filter chip, or null for `All`.
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

  /// `6 results`, as drawn opposite the `Available models` heading.
  String get resultsLabel {
    final count = visible.length;
    return count == 1 ? '1 result' : '$count results';
  }

  /// `6 REPOSITORIES · GGUF`, the overline above the title. Counts the whole
  /// catalog rather than the filtered view — it describes what the app offers.
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
