import '../../data/models/hf_repo_summary.dart';
import '../../data/sources/hf_api_client.dart';

/// What the Hugging Face · GGUF sheet is showing.
///
/// Pages accumulate into [repos]; [nextCursor] is the opaque token the Hub
/// hands back in its `Link` header, and a null one means the end of the list.
class CatalogState {
  const CatalogState({
    this.repos = const <HfRepoSummary>[],
    this.sort = CatalogSort.downloads,
    this.query = '',
    this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<HfRepoSummary> repos;
  final CatalogSort sort;
  final String query;
  final String? nextCursor;

  /// True while a further page is in flight, so the list can show one spinner
  /// at the bottom instead of replacing everything with a loading state.
  final bool isLoadingMore;

  /// Set when fetching a further page failed. The already-loaded repos stay on
  /// screen; only the footer changes to a retry.
  final String? loadMoreError;

  bool get hasMore => nextCursor != null;

  CatalogState copyWith({
    List<HfRepoSummary>? repos,
    CatalogSort? sort,
    String? query,
    String? nextCursor,
    bool clearCursor = false,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) => CatalogState(
    repos: repos ?? this.repos,
    sort: sort ?? this.sort,
    query: query ?? this.query,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}
