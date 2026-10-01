import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/sources/hf_api_client.dart';
import '../view_models/catalog_state.dart';
import 'catalog_repo_card.dart';
import 'filter_dropdown.dart';
import 'sheet_scaffold.dart';

/// The Hugging Face · GGUF browse sheet.
///
/// Dismissing it does not stop a download: progress lives in
/// `downloadViewModelProvider`, above this widget, so reopening the sheet
/// shows the same bar at the same percentage.
class AddModelSheet extends ConsumerStatefulWidget {
  const AddModelSheet({super.key});

  static Future<void> show(BuildContext context) =>
      SheetScaffold.show<void>(context, const AddModelSheet());

  @override
  ConsumerState<AddModelSheet> createState() => _AddModelSheetState();
}

class _AddModelSheetState extends ConsumerState<AddModelSheet> {
  /// How close to the bottom counts as "ask for more". Roughly two cards, so
  /// the next page is usually there before the user reaches the end.
  static const double _loadMoreThreshold = 400;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining > _loadMoreThreshold) return;
    // A no-op at the end of the list or while a page is in flight, so firing
    // it on every scroll frame is safe.
    ref.read(modelCatalogViewModelProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final catalog = ref.watch(modelCatalogViewModelProvider);

    return SheetScaffold.body(
      title: 'Hugging Face · GGUF',
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
            child: _Controls(
              controller: _search,
              sort: catalog.value?.sort ?? CatalogSort.downloads,
            ),
          ),
          SizedBox(height: metrics.gapMd),
          Expanded(
            child: catalog.when(
              data: (state) => _Results(state: state, controller: _scroll),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _CatalogError(error: error),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.controller, required this.sort});

  final TextEditingController controller;
  final CatalogSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    final notifier = ref.read(modelCatalogViewModelProvider.notifier);

    return Column(
      children: <Widget>[
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: notifier.search,
          onSubmitted: notifier.search,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Search repos',
            fillColor: palette.fieldFill,
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: palette.muted,
            ),
          ),
        ),
        SizedBox(height: metrics.gapSm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterDropdown<CatalogSort>(
            icon: Icons.sort_rounded,
            semanticLabel: 'Sort catalog',
            value: sort,
            options: <FilterOption<CatalogSort>>[
              for (final option in CatalogSort.values)
                (value: option, label: option.label),
            ],
            onSelected: notifier.setSort,
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.controller});

  final CatalogState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    if (state.repos.isEmpty) return const _NoResults();

    // One extra row for the footer: the spinner, the retry, or nothing.
    return ListView.separated(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.pagePadding,
      ),
      itemCount: state.repos.length + 1,
      separatorBuilder: (_, _) => SizedBox(height: metrics.gapMd),
      itemBuilder: (context, index) => index == state.repos.length
          ? _Footer(state: state)
          : CatalogRepoCard(repo: state.repos[index]),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final CatalogState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    final error = state.loadMoreError;

    if (error != null) {
      return Padding(
        padding: EdgeInsets.only(top: metrics.gapSm),
        child: Column(
          children: <Widget>[
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.danger),
            ),
            TextButton(
              onPressed: ref
                  .read(modelCatalogViewModelProvider.notifier)
                  .loadMore,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.gapLg),
        child: Text(
          'End of results',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.muted),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.gapLg),
      child: const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.metrics.pagePadding),
        child: Text(
          'No GGUF repositories matched that search.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.muted),
        ),
      ),
    );
  }
}

class _CatalogError extends ConsumerWidget {
  const _CatalogError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;

    final message = switch (error) {
      HfApiException(isRateLimit: true) =>
        'Hugging Face is rate-limiting — add a token in API keys.',
      HfApiException(:final message) => message,
      _ => 'Could not reach Hugging Face. Check your connection.',
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.all(metrics.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: palette.danger),
            ),
            SizedBox(height: metrics.gapMd),
            OutlinedButton(
              onPressed: ref.read(modelCatalogViewModelProvider.notifier).retry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
