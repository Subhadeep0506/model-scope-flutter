import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/catalog_model.dart';
import 'catalog_state.dart';

class CatalogViewModel extends AsyncNotifier<CatalogState> {
  @override
  Future<CatalogState> build() async {
    final models = await ref.read(catalogRepositoryProvider).load();
    return CatalogState(models: models);
  }

  void search(String query) {
    final existing = state.value;
    if (existing == null || existing.query == query) return;
    state = AsyncData<CatalogState>(existing.copyWith(query: query));
  }

  void filterBy(ModelCapability? capability) {
    final existing = state.value;
    if (existing == null || existing.capability == capability) return;
    state = AsyncData<CatalogState>(
      capability == null
          ? existing.copyWith(clearCapability: true)
          : existing.copyWith(capability: capability),
    );
  }

  Future<void> retry() async {
    state = const AsyncLoading<CatalogState>();
    state = await AsyncValue.guard(build);
  }
}
