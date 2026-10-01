import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The white, hairline-outlined, 10dp-radius container the mockups repeat for
/// the filter block, each session row and each row of the models sheet.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.borderColor,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    final body = Padding(
      padding: padding ?? EdgeInsets.all(metrics.gapMd),
      child: child,
    );

    return Material(
      color: color ?? palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: metrics.cardShape,
        side: BorderSide(color: borderColor ?? palette.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: height == null
            ? body
            : ConstrainedBox(
                // A minimum rather than a fixed height, so the row still grows
                // when the system text scale does.
                constraints: BoxConstraints(minHeight: height ?? 0),
                child: body,
              ),
      ),
    );
  }
}
