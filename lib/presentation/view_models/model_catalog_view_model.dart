import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../data/models/hf_repo_summary.dart';
import '../../data/sources/hf_api_client.dart';
import 'catalog_state.dart';

/// Drives the Hugging Face · GGUF browse sheet.
class ModelCatalogViewModel extends AsyncNotifier<CatalogState> {
  /// Long enough that typing a repo name is one request, short enough that the
  /// list does not feel stuck. Same idea as the system-prompt debounce in the
  /// Sampling sheet.
  static const Duration _typingPause = Duration(milliseconds: 350);

  static const String _logName = 'ModelCatalogViewModel';

  Timer? _searchTimer;

  @override
  Future<CatalogState> build() async {
    ref.onDispose(() => _searchTimer?.cancel());
    return _firstPage(const CatalogState());
  }

  /// Re-orders the catalog, discarding the pages already loaded — the cursor
  /// is only meaningful for the sort it came from.
  Future<void> setSort(CatalogSort sort) async {
    if (sort == current.sort) return;
    await _reload(current.copyWith(sort: sort));
  }

  /// Debounced free-text search. Safe to call on every keystroke.
  void search(String query) {
    _searchTimer?.cancel();
    if (query.trim() == current.query) return;
    _searchTimer = Timer(_typingPause, () {
      unawaited(_reload(current.copyWith(query: query.trim())));
    });
  }

  /// Fetches the next page and appends it.
  ///
  /// A no-op at the end of the list or while a page is already in flight, so
  /// the scroll listener can call it freely.
  Future<void> loadMore() async {
    final existing = current;
    if (!existing.hasMore || existing.isLoadingMore) return;

    state = AsyncData<CatalogState>(
      existing.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await ref
          .read(huggingFaceRepositoryProvider)
          .search(
            sort: existing.sort,
            query: existing.query,
            cursor: existing.nextCursor,
          );
      state = AsyncData<CatalogState>(
        current.copyWith(
          repos: <HfRepoSummary>[...current.repos, ...page.items],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not load another catalog page',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      // The pages already on screen stay; only the footer reports the failure.
      state = AsyncData<CatalogState>(
        current.copyWith(isLoadingMore: false, loadMoreError: '$error'),
      );
    }
  }

  /// Retries after a failure, keeping the current sort and query.
  Future<void> retry() => _reload(current);

  CatalogState get current => state.value ?? const CatalogState();

  Future<void> _reload(CatalogState base) async {
    state = const AsyncLoading<CatalogState>();
    state = await AsyncValue.guard(() => _firstPage(base));
  }

  Future<CatalogState> _firstPage(CatalogState base) async {
    final page = await ref
        .read(huggingFaceRepositoryProvider)
        .search(sort: base.sort, query: base.query);
    return CatalogState(
      repos: page.items,
      sort: base.sort,
      query: base.query,
      nextCursor: page.nextCursor,
    );
  }
}
