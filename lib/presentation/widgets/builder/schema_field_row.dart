import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../domain/services/schema_fields.dart';
import '../mono_label.dart';
import 'labelled_field.dart';

class SchemaFieldRow extends StatelessWidget {
  const SchemaFieldRow({
    super.key,
    required this.field,
    required this.onChanged,
    required this.onRemove,
    this.depth = 0,
  });

  final SchemaField field;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Container(
      margin: EdgeInsets.only(bottom: metrics.gapSm),
      padding: EdgeInsets.all(metrics.gapMd),
      decoration: BoxDecoration(
        color: depth.isEven ? palette.fieldFill : palette.surface,
        borderRadius: metrics.controlShape,
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: BuilderField(
                  value: field.name,
                  hint: 'field_name',
                  mono: true,
                  onChanged: (value) {
                    field.name = value;
                    onChanged();
                  },
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Expanded(
                flex: 2,
                child: _TypeDropdown(
                  value: field.type,
                  onChanged: (type) {
                    field.type = type;
                    onChanged();
                  },
                ),
              ),
              SizedBox(width: metrics.gapXs),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: palette.muted,
                tooltip: 'Remove this field',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          _RequiredToggle(field: field, onChanged: onChanged),
          if (field.type == SchemaFieldType.array) ...<Widget>[
            SizedBox(height: metrics.gapSm),
            _ItemsOf(field: field, onChanged: onChanged),
          ],
          if (field.type == SchemaFieldType.object)
            _Children(
              children: field.children,
              depth: depth,
              onChanged: onChanged,
            ),
          if (field.type == SchemaFieldType.array &&
              field.itemType == SchemaFieldType.object)
            _Children(
              children: field.itemChildren,
              depth: depth,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _Children extends StatelessWidget {
  const _Children({
    required this.children,
    required this.depth,
    required this.onChanged,
  });

  final List<SchemaField> children;
  final int depth;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(left: metrics.gapMd, top: metrics.gapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final child in children)
            SchemaFieldRow(
              key: ObjectKey(child),
              field: child,
              depth: depth + 1,
              onChanged: onChanged,
              onRemove: () {
                children.remove(child);
                onChanged();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                children.add(SchemaField());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add property'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsOf extends StatelessWidget {
  const _ItemsOf({required this.field, required this.onChanged});

  final SchemaField field;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const MonoLabel('ITEMS OF', variant: MonoStyle.overline),
      SizedBox(width: context.metrics.gapSm),
      Expanded(
        child: _TypeDropdown(
          value: field.itemType,

          exclude: const <SchemaFieldType>{SchemaFieldType.array},
          onChanged: (type) {
            field.itemType = type;
            onChanged();
          },
        ),
      ),
    ],
  );
}

class _RequiredToggle extends StatelessWidget {
  const _RequiredToggle({required this.field, required this.onChanged});

  final SchemaField field;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(
        height: 24,
        width: 24,
        child: Checkbox(
          value: field.required,
          onChanged: (value) {
            field.required = value ?? false;
            onChanged();
          },
        ),
      ),
      SizedBox(width: context.metrics.gapSm),
      Expanded(
        child: Text(
          'Required — the model must fill this in',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.palette.muted),
        ),
      ),
    ],
  );
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.value,
    required this.onChanged,
    this.exclude = const <SchemaFieldType>{},
  });

  final SchemaFieldType value;
  final ValueChanged<SchemaFieldType> onChanged;
  final Set<SchemaFieldType> exclude;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.gapSm),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: metrics.controlShape,
        border: Border.all(color: context.palette.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SchemaFieldType>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: metrics.cardShape,
          style: Theme.of(context).textTheme.bodySmall,
          items: <DropdownMenuItem<SchemaFieldType>>[
            for (final type in SchemaFieldType.values)
              if (!exclude.contains(type))
                DropdownMenuItem<SchemaFieldType>(
                  value: type,
                  child: Text(type.label),
                ),
          ],
          onChanged: (type) => type == null ? null : onChanged(type),
        ),
      ),
    );
  }
}
