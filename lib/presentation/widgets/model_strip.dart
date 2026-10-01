import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/model_descriptor.dart';
import 'icon_tile.dart';
import 'mono_label.dart';
import 'section_card.dart';

/// The bar under the chat header: which model is answering, its quantisation,
/// and the current temperature. Tapping it opens the Loaded models sheet.
class ModelStrip extends StatelessWidget {
  const ModelStrip({
    super.key,
    required this.model,
    required this.temperature,
    required this.onTap,
  });

  /// Null before anything has been installed.
  final ModelDescriptor? model;

  final double temperature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final current = model;

    return Row(
      children: <Widget>[
        Expanded(
          child: SectionCard(
            onTap: onTap,
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gapSm,
              vertical: metrics.gapSm,
            ),
            child: Row(
              children: <Widget>[
                const IconTile(icon: Icons.memory_rounded, size: 26),
                SizedBox(width: metrics.gapSm),
                Expanded(
                  child: Text(
                    current?.name ?? 'No model installed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: current == null ? palette.muted : null,
                    ),
                  ),
                ),
                if (current != null) ...<Widget>[
                  SizedBox(width: metrics.gapSm),
                  MonoLabel(current.quantization, variant: MonoStyle.tag),
                ],
              ],
            ),
          ),
        ),
        SizedBox(width: metrics.gapSm),
        _TemperaturePill(temperature: temperature),
      ],
    );
  }
}

class _TemperaturePill extends StatelessWidget {
  const _TemperaturePill({required this.temperature});

  final double temperature;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      label: 'Temperature',
      value: temperature.toStringAsFixed(2),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.gapSm,
          vertical: metrics.gapSm,
        ),
        decoration: BoxDecoration(
          color: palette.pill,
          borderRadius: BorderRadius.circular(metrics.radiusPill),
        ),
        child: MonoLabel(
          'T ${temperature.toStringAsFixed(2)}',
          variant: MonoStyle.tag,
          color: palette.primary,
        ),
      ),
    );
  }
}
