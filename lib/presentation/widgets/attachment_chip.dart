import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// A picked file, shown in the composer before sending and on the message
/// afterwards.
///
/// The bundled model is text-only, so this records the choice for display and
/// nothing more. The composer says so in a caption rather than letting the
/// limitation surprise you.
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.fileName, this.onRemove});

  final String fileName;

  /// Omit to render a read-only chip, as on a sent message.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final remove = onRemove;

    return Container(
      padding: EdgeInsets.fromLTRB(
        metrics.gapSm,
        metrics.gapXs,
        remove == null ? metrics.gapSm : metrics.gapXs,
        metrics.gapXs,
      ),
      decoration: BoxDecoration(
        color: palette.pill,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.attach_file_rounded, size: 14, color: palette.primary),
          SizedBox(width: metrics.gapXs),
          Flexible(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.ink),
            ),
          ),
          if (remove != null)
            IconButton(
              onPressed: remove,
              icon: const Icon(Icons.close_rounded, size: 14),
              color: palette.muted,
              tooltip: 'Remove $fileName',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}
