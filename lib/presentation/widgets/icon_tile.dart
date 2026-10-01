import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The soft green rounded square that carries an icon: the chat glyph on a
/// session row and the chip glyph on the model strip and model rows.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size,
    this.iconSize = 18,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double? size;
  final double iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final edge = size ?? metrics.squareButton;

    return Container(
      width: edge,
      height: edge,
      decoration: BoxDecoration(
        color: background ?? palette.iconTile,
        borderRadius: BorderRadius.circular(edge >= 32 ? 10 : 6),
      ),
      child: Icon(icon, size: iconSize, color: foreground ?? palette.primary),
    );
  }
}
