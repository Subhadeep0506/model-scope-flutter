import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../mono_label.dart';

class DataField {
  const DataField({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.flex = 1,
  });

  final String label;
  final String Function(Map<String, dynamic> row) cell;
  final bool numeric;

  final int flex;
}

class DataTableCard extends StatelessWidget {
  const DataTableCard({
    super.key,
    required this.columns,
    required this.rows,
    this.highlightRow,
    this.emptyMessage = 'The model returned no rows.',
  });

  final List<DataField> columns;
  final List<Map<String, dynamic>> rows;

  final bool Function(Map<String, dynamic> row)? highlightRow;

  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.gapMd),
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.muted),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.outline),
        borderRadius: metrics.controlShape,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _HeaderRow(columns: columns),
          for (final (index, row) in rows.indexed)
            _BodyRow(
              columns: columns,
              row: row,
              // A divider above every row but the first, rather than below
              // every row, so the table does not end on a stray line.
              topDivider: index > 0,
              highlighted: highlightRow?.call(row) ?? false,
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<DataField> columns;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Container(
      color: context.palette.pill,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapSm,
      ),
      child: Row(
        children: <Widget>[
          for (final (index, column) in columns.indexed) ...<Widget>[
            if (index > 0) SizedBox(width: metrics.gapSm),
            Expanded(
              flex: column.flex,
              child: Align(
                alignment: column.numeric
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: MonoLabel(
                  column.label.toUpperCase(),
                  variant: MonoStyle.overline,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  const _BodyRow({
    required this.columns,
    required this.row,
    required this.topDivider,
    required this.highlighted,
  });

  final List<DataField> columns;
  final Map<String, dynamic> row;
  final bool topDivider;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: highlighted ? palette.selectedTile : null,
        border: topDivider
            ? Border(top: BorderSide(color: palette.outline))
            : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final (index, column) in columns.indexed) ...<Widget>[
            if (index > 0) SizedBox(width: metrics.gapSm),
            Expanded(
              flex: column.flex,
              child: Text(
                _cellOf(column),
                textAlign: column.numeric ? TextAlign.right : TextAlign.left,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: highlighted ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _cellOf(DataField column) {
    final value = column.cell(row).trim();
    return value.isEmpty ? '—' : value;
  }
}
