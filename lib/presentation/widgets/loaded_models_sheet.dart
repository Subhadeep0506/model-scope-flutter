import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/model_descriptor.dart';
import 'icon_tile.dart';
import 'mono_label.dart';
import 'section_card.dart';
import 'sheet_scaffold.dart';

/// Switches which installed model answers. The throughput figure is the
/// measured rate of this session's last reply, not a headline number, and is
/// omitted until there is one.
class LoadedModelsSheet extends ConsumerWidget {
  const LoadedModelsSheet({super.key});

  static Future<void> show(BuildContext context) =>
      SheetScaffold.show<void>(context, const LoadedModelsSheet());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final library = ref.watch(modelLibraryViewModelProvider).value;
    final lastRun = ref.watch(chatViewModelProvider).lastMetrics;
    final models = library?.chatModels ?? const <ModelDescriptor>[];

    return SheetScaffold(
      title: 'Installed models',
      children: <Widget>[
        if (models.isEmpty)
          const _NoModels()
        else
          for (final model in models) ...<Widget>[
            _ModelRow(
              model: model,
              selected: model.id == library?.activeId,
              hasVision: library?.hasVision(model) ?? false,
              throughput: model.id == library?.activeId
                  ? lastRun?.tokensPerSecond
                  : null,
              onTap: () => _select(context, ref, model.id),
            ),
            SizedBox(height: metrics.gapSm),
          ],
      ],
    );
  }

  /// Switching releases the loaded weights; the chat reloads on its next
  /// prepare, so the sheet closes immediately rather than waiting.
  static Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final navigator = Navigator.of(context);
    await ref.read(modelLibraryViewModelProvider.notifier).setActive(id);
    await ref.read(chatViewModelProvider.notifier).reload();
    navigator.maybePop();
  }
}

class _NoModels extends StatelessWidget {
  const _NoModels();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Column(
      children: <Widget>[
        Text(
          'No models installed yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.muted),
        ),
        SizedBox(height: metrics.gapMd),
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).maybePop();
            context.go(Routes.settings);
          },
          child: const Text('Open settings'),
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.hasVision,
    required this.throughput,
    required this.onTap,
  });

  final ModelDescriptor model;
  final bool selected;
  final bool hasVision;
  final double? throughput;
  final VoidCallback onTap;

  String get _detail {
    final parts = <String>[model.quantization, model.sizeLabel];
    if (hasVision) parts.add('Vision');
    final rate = throughput;
    if (rate != null) parts.add('${rate.toStringAsFixed(1)} tok/s');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final theme = Theme.of(context);

    return Semantics(
      selected: selected,
      button: true,
      child: SectionCard(
        onTap: onTap,
        color: selected ? palette.selectedTile : palette.surface,
        borderColor: selected ? palette.primary : palette.outline,
        padding: EdgeInsets.all(metrics.gapMd),
        child: Row(
          children: <Widget>[
            IconTile(
              icon: Icons.memory_rounded,
              size: 28,
              background: selected ? palette.surface : palette.iconTile,
            ),
            SizedBox(width: metrics.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  MonoLabel(_detail, maxLines: 1),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: palette.primary),
          ],
        ),
      ),
    );
  }
}
