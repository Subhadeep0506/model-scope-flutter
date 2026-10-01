import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/model_descriptor.dart';
import 'mono_label.dart';
import 'section_card.dart';
import 'square_icon_button.dart';

/// One row of the Models list: title, repository, three mono chips, and trash.
///
/// Tapping the row makes the model active; the chips are informational only.
class InstalledModelCard extends StatelessWidget {
  const InstalledModelCard({
    super.key,
    required this.model,
    required this.isActive,
    required this.onSelect,
    required this.onRemove,
  });

  final ModelDescriptor model;

  /// The model Chat answers with, marked with a check.
  final bool isActive;

  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      selected: isActive,
      child: SectionCard(
        onTap: onSelect,
        color: isActive ? palette.selectedTile : null,
        borderColor: isActive ? palette.primary : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Details(model: model, isActive: isActive),
            ),
            SizedBox(width: metrics.gapSm),
            SquareIconButton(
              icon: Icons.delete_outline_rounded,
              label: 'Remove ${model.name}',
              size: 36,
              iconSize: 18,
              foreground: palette.muted,
              borderColor: palette.outline,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.model, required this.isActive});

  final ModelDescriptor model;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final params = model.paramLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (isActive) ...<Widget>[
              SizedBox(width: metrics.gapXs),
              Icon(Icons.check_rounded, size: 16, color: palette.primary),
            ],
          ],
        ),
        SizedBox(height: metrics.gapXs),
        MonoLabel(model.repoId, maxLines: 1),
        SizedBox(height: metrics.gapSm),
        Wrap(
          spacing: metrics.gapSm,
          runSpacing: metrics.gapSm,
          children: <Widget>[
            _Chip(text: model.quantization),
            _Chip(text: model.sizeLabel),
            if (params != null) _Chip(text: params),
          ],
        ),
      ],
    );
  }
}

/// The small outlined monospace tag the mockup repeats three times per row.
class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

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
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.radiusPill),
        border: Border.all(color: palette.outline),
      ),
      child: MonoLabel(text, variant: MonoStyle.tag),
    );
  }
}
