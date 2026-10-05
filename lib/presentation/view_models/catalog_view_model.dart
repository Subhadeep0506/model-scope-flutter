import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/catalog_model.dart';
import 'catalog_state.dart';

/// Drives the Model catalog screen. Loads the shipped manifest once, then does
/// nothing but filtering — it never touches the network, which is why the
/// search field responds on the keystroke.
class CatalogViewModel extends AsyncNotifier<CatalogState> {
  @override
  Future<CatalogState> build() async {
    final models = await ref.read(catalogRepositoryProvider).load();
    return CatalogState(models: models);
  }

  /// Free-text search over titles, repository ids and publishers.
  void search(String query) {
    final existing = state.value;
    if (existing == null || existing.query == query) return;
    state = AsyncData<CatalogState>(existing.copyWith(query: query));
  }

  /// Selects a capability chip. Pass null for `All`.
  void filterBy(ModelCapability? capability) {
    final existing = state.value;
    if (existing == null || existing.capability == capability) return;
    state = AsyncData<CatalogState>(
      capability == null
          ? existing.copyWith(clearCapability: true)
          : existing.copyWith(capability: capability),
    );
  }

  /// Retries after a failed manifest read — which only a corrupt build can
  /// cause, but the screen still offers the button rather than dead-ending.
  Future<void> retry() async {
    state = const AsyncLoading<CatalogState>();
    state = await AsyncValue.guard(build);
  }
}
