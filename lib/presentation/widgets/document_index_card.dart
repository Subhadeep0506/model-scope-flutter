import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/relative_time.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// What the Document QnA agent has indexed, and a way to throw it away.
///
/// The agent re-indexes whatever file you pick, so this is not needed to
/// change documents — it is here because the vectors of a document the user
/// has finished with are theirs to be rid of, and nothing else on the phone
/// shows that they exist.
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
            // Disabled rather than hidden, so the card reads the same whether
            // or not anything is indexed.
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
