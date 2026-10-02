import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/catalog_model.dart';
import '../../data/models/gguf_file.dart';
import 'capability_chip.dart';
import 'model_file_row.dart';
import 'mono_label.dart';
import 'sheet_scaffold.dart';

/// Everything one catalog entry holds: its quants, its adapters and its mmproj
/// files, each with the control that acts on it.
///
/// This is the only screen in the app that reads a repository's file tree, and
/// it does so once per model per run. Opening a model is therefore a single
/// request — the catalog list itself makes none.
class ModelDetailSheet extends ConsumerWidget {
  const ModelDetailSheet({super.key, required this.model});

  final CatalogModel model;

  /// Opens the sheet over the catalog, with the app's usual scrim and shape.
  static Future<void> show(BuildContext context, CatalogModel model) =>
      SheetScaffold.show<void>(context, ModelDetailSheet(model: model));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(repoFilesProvider(model.repoId));

    return SheetScaffold.body(
      title: model.name,
      titleAlign: TextAlign.left,
      body: CustomScrollView(
        slivers: <Widget>[
          _Padded(child: _Summary(model: model)),
          files.when(
            data: (files) => _FileList(model: model, files: files),
            loading: () => const _Padded(child: _Loading()),
            error: (error, _) => _Padded(
              child: _Failed(
                onRetry: () => ref.invalidate(repoFilesProvider(model.repoId)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One page-padded block inside the sheet's scroll view.
class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.model});

  final CatalogModel model;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MonoLabel(model.repoId, maxLines: 2),
        SizedBox(height: metrics.gapMd),
        Wrap(
          spacing: metrics.gapSm,
          runSpacing: metrics.gapSm,
          children: <Widget>[
            for (final capability in model.capabilities)
              CapabilityChip(capability: capability),
          ],
        ),
        SizedBox(height: metrics.gapLg),
        Text('Available files', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: metrics.gapXs),
        Text(
          'Choose a model quant to download. Adapter and MMProj files are '
          'shown for reference.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.muted),
        ),
        SizedBox(height: metrics.gapMd),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.model, required this.files});

  final CatalogModel model;
  final List<GgufFile> files;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    if (files.isEmpty) return const _Padded(child: _Empty());

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.pagePadding,
      ),
      sliver: SliverList.separated(
        itemCount: files.length,
        separatorBuilder: (_, _) => SizedBox(height: metrics.gapSm),
        itemBuilder: (context, index) => ModelFileRow(
          key: ValueKey<String>(files[index].id),
          model: model,
          file: files[index],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: context.metrics.gapXl),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: metrics.gapXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Could not reach Hugging Face. Check the connection, or add a '
            'token in Settings if this repository is gated.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.danger),
          ),
          SizedBox(height: metrics.gapSm),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: palette.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: metrics.gapXl),
      child: Text(
        'This repository holds no GGUF files the app can load.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    );
  }
}
