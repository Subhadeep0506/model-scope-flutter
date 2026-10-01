import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/byte_size.dart';
import '../../domain/services/model_downloader.dart';
import 'mono_label.dart';

/// The bar under a repo's chips once one of its quants is being fetched.
///
/// Also renders the two terminal states, because a download that cannot be
/// cancelled has to at least say how it ended.
class DownloadProgressBar extends StatelessWidget {
  const DownloadProgressBar({
    super.key,
    required this.progress,
    required this.onDismiss,
  });

  final DownloadProgress progress;

  /// Clears a finished or failed row. Unused while bytes are still arriving.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    final (value, caption, colour) = switch (progress) {
      Downloading(:final fraction, :final percent, :final received) => (
        fraction,
        fraction == null
            ? 'downloading ${formatBytes(received)}'
            : 'downloading $percent%',
        palette.primary,
      ),
      DownloadCompleted() => (1.0, 'installed', palette.primary),
      DownloadFailed(:final message) => (1.0, message, palette.danger),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: metrics.gapSm),
        ClipRRect(
          borderRadius: BorderRadius.circular(metrics.radiusPill),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: palette.fieldFill,
            color: colour,
          ),
        ),
        SizedBox(height: metrics.gapXs + 2),
        Row(
          children: <Widget>[
            Expanded(child: MonoLabel(caption, color: colour, maxLines: 2)),
            if (progress is! Downloading)
              InkWell(
                onTap: onDismiss,
                child: Padding(
                  padding: EdgeInsets.all(metrics.gapXs),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: palette.muted,
                    semanticLabel: 'Dismiss',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
