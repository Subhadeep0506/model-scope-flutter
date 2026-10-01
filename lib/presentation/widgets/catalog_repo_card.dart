import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/gguf_file.dart';
import '../../data/models/hf_repo_summary.dart';
import '../../domain/services/model_downloader.dart';
import '../../data/sources/hf_api_client.dart';
import 'download_progress_bar.dart';
import 'mono_label.dart';
import 'quant_chip.dart';
import 'section_card.dart';

/// One repository in the browse sheet: title, stats, and its quant chips.
///
/// The file list is fetched by watching `repoFilesProvider` from `build`. That
/// is the whole laziness mechanism — a card only builds when the list scrolls
/// it near the viewport, so only visible repos cost a request, and Riverpod's
/// per-argument cache means scrolling back does not fetch again.
class CatalogRepoCard extends ConsumerWidget {
  const CatalogRepoCard({super.key, required this.repo});

  final HfRepoSummary repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;
    final files = ref.watch(repoFilesProvider(repo.id));

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MonoLabel(
            repo.id,
            variant: MonoStyle.sliderValue,
            color: palette.ink,
            maxLines: 1,
          ),
          SizedBox(height: metrics.gapXs),
          MonoLabel(repo.statsLabel),
          SizedBox(height: metrics.gapMd),
          files.when(
            data: (list) => _Quants(repo: repo, files: list),
            loading: () => const _ChipsPlaceholder(),
            error: (error, _) => _FilesError(
              message: _describe(error),
              onRetry: () => ref.invalidate(repoFilesProvider(repo.id)),
            ),
          ),
        ],
      ),
    );
  }

  static String _describe(Object error) => switch (error) {
    HfApiException(isRateLimit: true) =>
      'Hugging Face is rate-limiting — add a token in API keys.',
    HfApiException(:final message) => message,
    _ => 'Could not list files for this repository.',
  };
}

class _Quants extends ConsumerWidget {
  const _Quants({required this.repo, required this.files});

  final HfRepoSummary repo;
  final List<GgufFile> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;

    if (files.isEmpty) {
      return Text(
        'No loadable GGUF files in this repository.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: palette.muted),
      );
    }

    final downloads = ref.watch(downloadViewModelProvider);
    final library = ref.watch(modelLibraryViewModelProvider).value;
    final notifier = ref.read(downloadViewModelProvider.notifier);

    // One bar per in-flight or just-finished file of this repo. Normally there
    // is at most one, but nothing stops a user starting two quants.
    final active = <String, DownloadProgress>{
      for (final file in files) file.id: ?downloads[file.id],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: metrics.gapSm,
          runSpacing: metrics.gapSm,
          children: <Widget>[
            for (final file in files)
              QuantChip(
                file: file,
                state: _stateOf(
                  file,
                  downloads[file.id],
                  library?.byId(file.id) != null,
                ),
                onPressed: downloads[file.id] is Downloading
                    ? null
                    : () => notifier.start(repo: repo, file: file),
              ),
          ],
        ),
        for (final entry in active.entries)
          DownloadProgressBar(
            progress: entry.value,
            onDismiss: () => notifier.dismiss(entry.key),
          ),
      ],
    );
  }

  static QuantChipState _stateOf(
    GgufFile file,
    DownloadProgress? progress,
    bool installed,
  ) {
    if (installed) return QuantChipState.installed;
    if (progress is Downloading) return QuantChipState.downloading;
    return file.isHeavy ? QuantChipState.heavy : QuantChipState.idle;
  }
}

/// Holds the card's height steady while the tree request is in flight, so the
/// list does not jump under the finger as rows resolve.
class _ChipsPlaceholder extends StatelessWidget {
  const _ChipsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Row(
      children: <Widget>[
        for (final width in <double>[120, 120])
          Padding(
            padding: EdgeInsets.only(right: metrics.gapSm),
            child: Container(
              width: width,
              height: 26,
              decoration: BoxDecoration(
                color: palette.fieldFill,
                borderRadius: BorderRadius.circular(metrics.radiusPill),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilesError extends StatelessWidget {
  const _FilesError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.danger),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
