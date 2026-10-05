import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/catalog_model.dart';

/// `All · Text to text · Image to text · Tool calling`, scrolling sideways
/// rather than wrapping, so adding a chip cannot move the heading below it.
class CapabilityFilterBar extends StatelessWidget {
  const CapabilityFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// The active capability, or null for `All`.
  final ModelCapability? selected;

  /// Called with null when `All` is tapped.
  final ValueChanged<ModelCapability?> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SizedBox(
      height: metrics.control,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ModelCapability.values.length + 1,
        separatorBuilder: (_, _) => SizedBox(width: metrics.gapSm),
        itemBuilder: (context, index) {
          final capability = index == 0
              ? null
              : ModelCapability.values[index - 1];
          return _FilterChip(
            label: capability?.label ?? 'All',
            isSelected: capability == selected,
            onTap: () => onSelected(capability),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    // One node for the whole chip. Without `container` and `excludeSemantics`
    // a screen reader announces it twice and the selected state lands on
    // neither reading.
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: '$label models',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: isSelected ? palette.primary : palette.fieldFill,
        shape: RoundedRectangleBorder(
          borderRadius: metrics.controlShape,
          side: BorderSide(
            color: isSelected ? palette.primary : palette.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.gapLg),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isSelected ? palette.onPrimary : palette.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
