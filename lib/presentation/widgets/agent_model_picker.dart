import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/model_descriptor.dart';
import 'icon_tile.dart';
import 'mono_label.dart';
import 'section_card.dart';

class AgentModelPicker extends StatelessWidget {
  const AgentModelPicker({
    super.key,
    required this.models,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ModelDescriptor> models;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final theme = Theme.of(context);

    return SectionCard(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapSm,
      ),
      child: Row(
        children: <Widget>[
          const IconTile(icon: Icons.memory_rounded, size: 30),
          SizedBox(width: metrics.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MonoLabel('MODEL', variant: MonoStyle.overline),
                if (models.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: metrics.gapSm),
                    child: Text(
                      'No model installed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  )
                else
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _valueOf(models, selectedId),
                      isExpanded: true,
                      isDense: true,
                      borderRadius: metrics.cardShape,
                      padding: EdgeInsets.zero,
                      style: theme.textTheme.titleSmall,
                      items: <DropdownMenuItem<String>>[
                        for (final model in models)
                          DropdownMenuItem<String>(
                            value: model.id,
                            child: Text(
                              model.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => id == null ? null : onSelected(id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _valueOf(List<ModelDescriptor> models, String? selected) {
    for (final model in models) {
      if (model.id == selected) return selected;
    }
    return models.isEmpty ? null : models.first.id;
  }
}
