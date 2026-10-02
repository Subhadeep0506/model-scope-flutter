import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';

/// The soft-filled search box drawn on the Chats screen and the Model catalog.
///
/// Unlike the outlined fields elsewhere it reads as a fill with no hairline
/// until it takes focus, which is how both mockups draw it.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hintText,
        fillColor: palette.fieldFill,
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: palette.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: metrics.gapMd),
        border: _border(metrics, BorderSide.none),
        enabledBorder: _border(metrics, BorderSide.none),
        focusedBorder: _border(
          metrics,
          BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
    );
  }

  OutlineInputBorder _border(AppMetrics metrics, BorderSide side) =>
      OutlineInputBorder(borderRadius: metrics.controlShape, borderSide: side);
}
