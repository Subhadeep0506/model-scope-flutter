import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/download_progress.dart';
import 'mono_label.dart';
import 'square_icon_button.dart';

/// The progress bar and transport controls shown under a file row while its
/// download is live. The transfer belongs to the operating system and can be
/// suspended, so the row offers pause, resume and cancel.
class DownloadControls extends StatelessWidget {
  const DownloadControls({
    super.key,
    required this.progress,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDismiss,
  });

  final DownloadProgress progress;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  /// Clears a finished or failed row, returning it to its download button.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final (value, caption, colour) = _appearance(palette);

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
            ..._actions(palette),
          ],
        ),
      ],
    );
  }

  /// Bar value, caption and colour for each state. A null value leaves the bar
  /// indeterminate, which is the honest rendering of a queued transfer.
  (double?, String, Color) _appearance(AppPalette palette) =>
      switch (progress) {
        DownloadQueued() => (null, 'queued', palette.muted),
        Downloading(:final percent) => (
          percent / 100,
          'downloading $percent%',
          palette.primary,
        ),
        DownloadPaused(:final fraction, :final caption) => (
          fraction,
          caption,
          palette.warning,
        ),
        DownloadCompleted() => (1.0, 'installed', palette.primary),
        DownloadFailed(:final message) => (1.0, message, palette.danger),
        DownloadCancelled() => (0.0, 'cancelled', palette.muted),
      };

  List<Widget> _actions(AppPalette palette) => switch (progress) {
    DownloadQueued() => <Widget>[_cancel(palette)],
    Downloading(:final canPause) => <Widget>[
      if (canPause)
        _button(palette, Icons.pause_rounded, 'Pause download', onPause),
      _cancel(palette),
    ],
    DownloadPaused() => <Widget>[
      _button(palette, Icons.play_arrow_rounded, 'Resume download', onResume),
      _cancel(palette),
    ],
    _ => <Widget>[_button(palette, Icons.close_rounded, 'Dismiss', onDismiss)],
  };

  Widget _cancel(AppPalette palette) =>
      _button(palette, Icons.close_rounded, 'Cancel download', onCancel);

  Widget _button(
    AppPalette palette,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: SquareIconButton(
      icon: icon,
      label: label,
      size: 32,
      iconSize: 16,
      foreground: palette.ink,
      borderColor: palette.outline,
      onPressed: onPressed,
    ),
  );
}
