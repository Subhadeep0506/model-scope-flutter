import 'package:flutter/material.dart';

import '../../config/theme/app_palette.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.color,
  });

  final String title;

  final String? actionLabel;
  final VoidCallback? onAction;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = actionLabel;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: color ?? palette.muted),
          ),
        ),
        if (label != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: palette.primary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label),
          ),
      ],
    );
  }
}
