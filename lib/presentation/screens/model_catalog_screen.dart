import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/catalog_model.dart';
import '../view_models/catalog_state.dart';
import '../widgets/capability_filter_bar.dart';
import '../widgets/catalog_model_card.dart';
import '../widgets/model_detail_sheet.dart';
import '../widgets/mono_label.dart';
import '../widgets/search_field.dart';
import '../widgets/square_icon_button.dart';

/// The models this build offers, with a search field and capability filters.
/// Both filter a shipped manifest, so the only traffic this screen makes is
/// one stats call per card, once per app run.
class ModelCatalogScreen extends ConsumerStatefulWidget {
  const ModelCatalogScreen({super.key});

  @override
  ConsumerState<ModelCatalogScreen> createState() => _ModelCatalogScreenState();
}

class _ModelCatalogScreenState extends ConsumerState<ModelCatalogScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final catalog = ref.watch(catalogViewModelProvider);
    final state = catalog.value;
    final notifier = ref.read(catalogViewModelProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            _Block(
              top: metrics.gapLg,
              child: _Header(state: state),
            ),
            _Block(
              top: metrics.gapLg,
              child: SearchField(
                controller: _search,
                hintText: 'Search models or publishers',
                onChanged: notifier.search,
              ),
            ),
            _Block(
              top: metrics.gapMd,
              child: CapabilityFilterBar(
                selected: state?.capability,
                onSelected: notifier.filterBy,
              ),
            ),
            _Block(
              top: metrics.gapLg,
              child: _ListHeading(state: state),
            ),
            if (state != null)
              _Results(models: state.visible)
            else if (catalog.hasError)
              _Block(
                top: metrics.gapXl,
                child: _Failed(onRetry: notifier.retry),
              )
            else
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final CatalogState? state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SquareIconButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to settings',
          foreground: palette.ink,
          borderColor: palette.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MonoLabel(state?.overline ?? 'GGUF', variant: MonoStyle.overline),
              const SizedBox(height: 2),
              Text(
                'Model catalog',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `Available models` opposite `6 results`.
class _ListHeading extends StatelessWidget {
  const _ListHeading({required this.state});

  final CatalogState? state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = state;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Available models',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: palette.muted),
          ),
        ),
        if (count != null) MonoLabel(count.resultsLabel),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.models});

  final List<CatalogModel> models;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    if (models.isEmpty) {
      return _Block(top: metrics.gapXl, child: const _NoMatches());
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        metrics.gapXl,
      ),
      sliver: SliverList.separated(
        itemCount: models.length,
        separatorBuilder: (_, _) => SizedBox(height: metrics.gapMd),
        itemBuilder: (context, index) => CatalogModelCard(
          key: ValueKey<String>(models[index].repoId),
          model: models[index],
          onTap: () => ModelDetailSheet.show(context, models[index]),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) => Text(
    'No models match that search.',
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted),
  );
}

/// Only a corrupt build can get here — the manifest is an asset — but the
/// screen offers the button rather than dead-ending on a blank list.
class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'The model catalog could not be read.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.danger),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: palette.primary),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// One page-padded row in the scroll view, as on the Settings screen.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.top = 0});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        top,
        metrics.pagePadding,
        0,
      ),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}
