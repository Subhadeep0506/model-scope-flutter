import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'icon_tile.dart';

/// One choice in a [FilterDropdown].
typedef FilterOption<T> = ({T value, String label});

/// The soft-filled chip with a leading glyph and a trailing chevron used for
/// "All models" and "All time" on the Chats screen.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;

  /// Describes the control itself, e.g. "Filter by model".
  final String semanticLabel;

  final T value;
  final List<FilterOption<T>> options;
  final ValueChanged<T> onSelected;

  String get _label => options
      .firstWhere(
        (option) => option.value == value,
        orElse: () => options.first,
      )
      .label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      button: true,
      label: semanticLabel,
      value: _label,
      child: PopupMenuButton<T>(
        initialValue: value,
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        tooltip: semanticLabel,
        color: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: metrics.cardShape),
        itemBuilder: (_) => <PopupMenuEntry<T>>[
          for (final option in options)
            PopupMenuItem<T>(value: option.value, child: Text(option.label)),
        ],
        child: _ChipBody(icon: icon, label: _label),
      ),
    );
  }
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      constraints: BoxConstraints(minHeight: metrics.control),
      padding: EdgeInsets.symmetric(horizontal: metrics.gapSm),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: metrics.controlShape,
      ),
      child: Row(
        children: <Widget>[
          IconTile(
            icon: icon,
            size: 24,
            iconSize: 14,
            background: palette.surface,
          ),
          SizedBox(width: metrics.gapSm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: palette.muted,
          ),
        ],
      ),
    );
  }
}
