import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The square button used for `+`, back, tune, attach, send and sheet close.
/// All share one 44dp square; only the fill, border and icon colour change.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.background,
    this.foreground,
    this.borderColor,
    this.size,
    this.iconSize = 20,
  });

  final IconData icon;

  /// Spoken by screen readers. Required so no control is unlabelled.
  final String label;

  /// `null` renders the button disabled.
  final VoidCallback? onPressed;

  final Color? background;
  final Color? foreground;

  /// Omit for a borderless button, as on `+` and send.
  final Color? borderColor;

  final double? size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final edge = size ?? metrics.squareButton;
    final border = borderColor;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Material(
        color: background ?? palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: metrics.controlShape,
          side: border == null
              ? BorderSide.none
              : BorderSide(color: border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: edge,
            height: edge,
            child: Icon(icon, size: iconSize, color: foreground ?? palette.ink),
          ),
        ),
      ),
    );
  }
}
