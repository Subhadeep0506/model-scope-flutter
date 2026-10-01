import 'package:flutter/material.dart';

import '../../config/theme/app_palette.dart';

/// A Settings section title, optionally with a text action on the right.
///
/// `Models · 8.06 GB` and its green `Add model` link are one of these; the
/// plainer `Appearance` and `Storage` headings are the same widget without an
/// action.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;

  /// Omit for a heading with no trailing action.
  final String? actionLabel;
  final VoidCallback? onAction;

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
                ?.copyWith(color: palette.muted),
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
