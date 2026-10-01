import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/gguf_file.dart';
import 'mono_label.dart';

/// A downloadable quantisation: `⤓ Q4_K_M · 1.10 GB`.
///
/// Heavy files are marked rather than hidden — the threshold is a guess about
/// the device, and a tablet may well cope — so the chip states the risk and
/// still lets the user decide.
class QuantChip extends StatelessWidget {
  const QuantChip({
    super.key,
    required this.file,
    required this.state,
    required this.onPressed,
  });

  final GgufFile file;
  final QuantChipState state;

  /// Null while the file is downloading or already installed.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    final (border, foreground) = switch (state) {
      QuantChipState.installed => (palette.primary, palette.primary),
      QuantChipState.downloading => (palette.primary, palette.primary),
      QuantChipState.heavy => (palette.warning, palette.warning),
      QuantChipState.idle => (palette.outline, palette.ink),
    };

    final icon = switch (state) {
      QuantChipState.installed => Icons.check_rounded,
      QuantChipState.heavy => Icons.warning_amber_rounded,
      _ => Icons.download_rounded,
    };

    return Semantics(
      button: onPressed != null,
      label: switch (state) {
        QuantChipState.installed => 'Installed: ${file.chipLabel}',
        QuantChipState.downloading => 'Downloading ${file.chipLabel}',
        QuantChipState.heavy =>
          'Download ${file.chipLabel}. Large — may not load on this device.',
        QuantChipState.idle => 'Download ${file.chipLabel}',
      },
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.radiusPill),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gapSm,
              vertical: metrics.gapXs + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 14, color: foreground),
                SizedBox(width: metrics.gapXs + 2),
                MonoLabel(
                  file.chipLabel,
                  variant: MonoStyle.tag,
                  color: foreground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How a [QuantChip] is drawn, worked out by the card that owns it.
enum QuantChipState { idle, heavy, downloading, installed }
