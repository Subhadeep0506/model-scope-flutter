import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/hf_repo_summary.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';
import 'package:model_scope_flutter/presentation/view_models/catalog_state.dart';
import 'package:model_scope_flutter/presentation/view_models/model_catalog_view_model.dart';

import '../support/fakes.dart';

/// Drives the catalog's first page to completion when it is going to fail.
///
/// Awaiting `.future` would mean awaiting a rejection; listening instead lets
/// the error land on the provider, which is where the sheet reads it from.
Future<void> pumpFailedBuild(ProviderContainer container) async {
  container.listen<AsyncValue<CatalogState>>(
    modelCatalogViewModelProvider,
    (_, _) {},
    onError: (_, _) {},
  );
  while (!container.read(modelCatalogViewModelProvider).hasError) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHuggingFaceRepository catalog;
  late ProviderContainer container;

  /// Two pages: `a/one` then `a/two`, with `'1'` as the cursor between them.
  List<HfRepoPage> twoPages() => <HfRepoPage>[
    HfRepoPage(
      items: <HfRepoSummary>[fakeRepo(id: 'a/one')],
      nextCursor: '1',
    ),
    HfRepoPage(items: <HfRepoSummary>[fakeRepo(id: 'a/two')], nextCursor: null),
  ];

  ProviderContainer containerWith(List<HfRepoPage> pages) {
    catalog = FakeHuggingFaceRepository(pages: pages);
    return ProviderContainer.test(
      retry: noRetry,
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(),
        huggingFace: catalog,
      ),
    );
  }

  ModelCatalogViewModel notifier() =>
      container.read(modelCatalogViewModelProvider.notifier);

  CatalogState state() =>
      container.read(modelCatalogViewModelProvider).value ??
      const CatalogState();

  test('the first page loads sorted by downloads', () async {
    // Arrange
    container = containerWith(twoPages());

    // Act
    await container.read(modelCatalogViewModelProvider.future);

    // Assert — downloads is the default because it is the only ordering that
    // puts usable, widely-run models at the top of a cold list.
    check(state().repos.map((r) => r.id)).deepEquals(<String>['a/one']);
    check(catalog.searches.single.sort).equals(CatalogSort.downloads);
    check(catalog.searches.single.cursor).isNull();
    check(state().hasMore).isTrue();
  });

  test('loadMore appends the next page and advances the cursor', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);

    // Act
    await notifier().loadMore();

    // Assert — appended, not replaced; the sheet scrolls on rather than jumps.
    check(state().repos.map((r) => r.id))
        .deepEquals(<String>['a/one', 'a/two']);
    check(catalog.searches.last.cursor).equals('1');
    check(state().hasMore).isFalse();
  });

  test('loadMore at the end of the list asks for nothing', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    await notifier().loadMore();
    final requests = catalog.searches.length;

    // Act — the scroll listener keeps firing as the user bounces the end.
    await notifier().loadMore();
    await notifier().loadMore();

    // Assert
    check(catalog.searches).length.equals(requests);
  });

  test('a failed page keeps the loaded repos and reports in the '
      'footer', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    catalog.failure = const HfApiException('Hugging Face is rate-limiting');

    // Act
    await notifier().loadMore();

    // Assert — losing the whole list over one failed page would be worse than
    // the failure itself.
    check(state().repos).length.equals(1);
    check(state().isLoadingMore).isFalse();
    check(state().loadMoreError).isNotNull();
  });

  test('changing the sort starts the list again', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    await notifier().loadMore();

    // Act
    await notifier().setSort(CatalogSort.likes);

    // Assert — the cursor belongs to the old ordering, so the pages go too.
    check(state().repos.map((r) => r.id)).deepEquals(<String>['a/one']);
    check(state().sort).equals(CatalogSort.likes);
    check(catalog.searches.last.cursor).isNull();
  });

  test('selecting the sort already in use does not refetch', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    final requests = catalog.searches.length;

    // Act
    await notifier().setSort(CatalogSort.downloads);

    // Assert
    check(catalog.searches).length.equals(requests);
  });

  test('a burst of keystrokes collapses into one search', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    final requests = catalog.searches.length;

    // Act — typing "qwen" one character at a time.
    notifier()
      ..search('q')
      ..search('qw')
      ..search('qwe')
      ..search('qwen');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Assert — one request, for the finished word.
    check(catalog.searches).length.equals(requests + 1);
    check(catalog.searches.last.query).equals('qwen');
  });

  test('retyping the same query does not search again', () async {
    // Arrange
    container = containerWith(twoPages());
    await container.read(modelCatalogViewModelProvider.future);
    notifier().search('qwen');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final requests = catalog.searches.length;

    // Act — trailing whitespace is not a new search.
    notifier().search('  qwen  ');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Assert
    check(catalog.searches).length.equals(requests);
  });

  test('a failed first page surfaces as an error state', () async {
    // Arrange
    container = containerWith(twoPages());
    catalog.failure = const HfApiException('No connection to Hugging Face.');

    // Act
    await pumpFailedBuild(container);

    // Assert — the sheet shows a retry rather than an empty list, which would
    // read as "no models match".
    check(container.read(modelCatalogViewModelProvider).hasError).isTrue();
  });

  test('retry re-runs the current sort and query', () async {
    // Arrange
    container = containerWith(twoPages());
    catalog.failure = const HfApiException('No connection to Hugging Face.');
    await pumpFailedBuild(container);
    catalog.failure = null;

    // Act
    await notifier().retry();

    // Assert
    check(state().repos.map((r) => r.id)).deepEquals(<String>['a/one']);
  });
}
