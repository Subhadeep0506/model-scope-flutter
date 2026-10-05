import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/byte_size.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// What the app itself is holding on disk, and a way to let it go. Downloaded
/// weights are excluded on purpose — those are removed one at a time from the
/// Models list, where the cost of each is visible.
class StorageCard extends ConsumerWidget {
  const StorageCard({super.key});

  /// Reference point for the bar only; there is no quota to report.
  static const int _barCeilingBytes = 500 * 1000 * 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    final bytes = ref.watch(storageViewModelProvider);

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Cache',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MonoLabel(
                bytes.value == null ? '—' : formatBytes(bytes.value ?? 0),
                variant: MonoStyle.sliderValue,
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(metrics.radiusPill),
            child: LinearProgressIndicator(
              value: bytes.value == null
                  ? null
                  : ((bytes.value ?? 0) / _barCeilingBytes).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: palette.fieldFill,
              color: palette.primary,
            ),
          ),
          SizedBox(height: metrics.gapSm),
          Text(
            'Transcripts and temporary files. Downloaded models are not '
            'touched — remove those from the list above.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
          SizedBox(height: metrics.gapMd),
          OutlinedButton.icon(
            onPressed: bytes.isLoading
                ? null
                : ref.read(storageViewModelProvider.notifier).clear,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear cache'),
          ),
        ],
      ),
    );
  }
}
