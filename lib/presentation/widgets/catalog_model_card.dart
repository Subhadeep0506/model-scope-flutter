import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/byte_size.dart';
import '../../data/models/catalog_model.dart';
import 'capability_chip.dart';
import 'icon_tile.dart';
import 'mono_chip.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// One row of the Model catalog: everything the manifest knows, plus a stats
/// line fetched from Hugging Face. Nothing depends on the stats — if the Hub
/// is slow or unreachable the row renders without them.
class CatalogModelCard extends ConsumerWidget {
  const CatalogModelCard({super.key, required this.model, required this.onTap});

  final CatalogModel model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;

    return SectionCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const IconTile(icon: Icons.smart_toy_outlined, size: 40),
          SizedBox(width: metrics.gapMd),
          Expanded(child: _Details(model: model)),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.model});

  final CatalogModel model;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TitleRow(name: model.name),
        SizedBox(height: metrics.gapXs),
        MonoLabel(model.repoId, maxLines: 1),
        SizedBox(height: metrics.gapSm),
        Text(
          model.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.muted),
        ),
        SizedBox(height: metrics.gapSm),
        _Tags(model: model),
        SizedBox(height: metrics.gapSm),
        _Stats(repoId: model.repoId),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 20, color: palette.muted),
      ],
    );
  }
}

class _Tags extends ConsumerWidget {
  const _Tags({required this.model});

  final CatalogModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final params = model.paramLabel;
    final isInstalled = ref.watch(isRepoInstalledProvider(model.repoId));

    return Wrap(
      spacing: metrics.gapSm,
      runSpacing: metrics.gapSm,
      children: <Widget>[
        if (params != null) MonoChip(params),
        for (final capability in model.capabilities)
          CapabilityChip(capability: capability),
        if (isInstalled) const _InstalledBadge(),
      ],
    );
  }
}

/// The filled green `Installed` tag. Filled rather than outlined so it reads
/// as a state already reached, not another thing to choose.
class _InstalledBadge extends StatelessWidget {
  const _InstalledBadge();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapSm,
        vertical: metrics.gapXs + 1,
      ),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check_rounded, size: 12, color: palette.onPrimary),
          SizedBox(width: metrics.gapXs),
          MonoLabel(
            'Installed',
            variant: MonoStyle.tag,
            color: palette.onPrimary,
          ),
        ],
      ),
    );
  }
}

/// `182k · 412 · 3 files`, once the Hub answers.
class _Stats extends ConsumerWidget {
  const _Stats({required this.repoId});

  final String repoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(repoStatsProvider(repoId)).value;
    if (stats == null) return const SizedBox.shrink();

    final metrics = context.metrics;
    return Semantics(
      label: '${stats.statsLabel}, ${stats.fileCountLabel}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          _Stat(
            icon: Icons.download_rounded,
            text: formatCount(stats.downloads),
          ),
          SizedBox(width: metrics.gapMd),
          _Stat(
            icon: Icons.favorite_border_rounded,
            text: formatCount(stats.likes),
          ),
          SizedBox(width: metrics.gapMd),
          MonoLabel(stats.fileCountLabel),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: palette.muted),
        SizedBox(width: metrics.gapXs),
        MonoLabel(text),
      ],
    );
  }
}
