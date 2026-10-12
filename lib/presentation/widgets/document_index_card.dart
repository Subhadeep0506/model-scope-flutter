import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/relative_time.dart';
import 'mono_label.dart';
import 'section_card.dart';

class DocumentIndexCard extends ConsumerWidget {
  const DocumentIndexCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final metrics = context.metrics;
    final index = ref.watch(documentIndexProvider);
    final indexed = index.document;

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
                  'Document index',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MonoLabel(
                '${index.chunks} ${index.chunks == 1 ? 'PASSAGE' : 'PASSAGES'}',
                variant: MonoStyle.sliderValue,
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          Text(
            indexed == null
                ? 'Nothing indexed yet. Pick a document on the Document QnA '
                      'agent and it will be read and encoded here.'
                : '${indexed.title}, indexed '
                      '${formatAgo(indexed.ingestedAt, DateTime.now())}.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
          SizedBox(height: metrics.gapMd),
          OutlinedButton.icon(
            onPressed: index.chunks == 0
                ? null
                : ref.read(documentIndexProvider.notifier).clear,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear index'),
          ),
        ],
      ),
    );
  }
}
