import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/catalog_model.dart';
import 'mono_label.dart';

/// The small icon-and-label tag naming one thing a model can do.
///
/// Read-only, and drawn on every catalog card and at the head of the model
/// sheet. The selectable chips above the list are a separate control — see
/// `CapabilityFilterBar` — because those are buttons and these are labels.
class CapabilityChip extends StatelessWidget {
  const CapabilityChip({super.key, required this.capability});

  final ModelCapability capability;

  /// The glyph for each capability.
  ///
  /// Lives here rather than on [ModelCapability] so the data layer stays free
  /// of Flutter: an [IconData] on the enum would drag `material.dart` into a
  /// model that is otherwise plain Dart and decodes on an isolate.
  static IconData iconOf(ModelCapability capability) => switch (capability) {
    ModelCapability.textToText => Icons.notes_rounded,
    ModelCapability.imageToText => Icons.image_outlined,
    ModelCapability.toolCalling => Icons.build_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapSm,
        vertical: metrics.gapXs + 1,
      ),
      decoration: BoxDecoration(
        color: palette.pill,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
        border: Border.all(color: palette.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconOf(capability), size: 12, color: palette.primary),
          SizedBox(width: metrics.gapXs + 1),
          MonoLabel(capability.label, variant: MonoStyle.tag),
        ],
      ),
    );
  }
}
