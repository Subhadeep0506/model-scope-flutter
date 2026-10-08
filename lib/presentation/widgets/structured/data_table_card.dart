import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../mono_label.dart';

/// One column of a [DataTableCard].
///
/// Not named `DataColumn`: Material exports one of those, and a widget file
/// that imports both would have to prefix every use.
class DataField {
  const DataField({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.flex = 1,
  });

  /// The mono heading, e.g. `RETAILER`.
  final String label;

  /// What to print for one row. Returns an empty string for a field the model
  /// left out, which the table draws as a dash.
  final String Function(Map<String, dynamic> row) cell;

  /// Right-aligned, for figures. A column of prices that does not line up on
  /// the decimal point is far harder to compare.
  final bool numeric;

  final int flex;
}

/// The table every structured view draws its rows in.
///
/// Not Flutter's `DataTable`: that scrolls horizontally and sizes columns to
/// their content, which on a phone means a price column pushed off the right
/// edge. This lays columns out by flex so everything fits the width there is.
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

  /// Which row to tint, e.g. the cheapest offer. Null tints none.
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

  /// A dash rather than a blank for a field the model left out: an empty cell
  /// reads as a layout fault, a dash reads as missing data — which is what it
  /// is, and worth seeing.
  String _cellOf(DataField column) {
    final value = column.cell(row).trim();
    return value.isEmpty ? '—' : value;
  }
}
