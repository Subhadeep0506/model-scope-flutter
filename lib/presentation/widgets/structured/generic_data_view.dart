import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../data/models/json_read.dart';
import '../mono_label.dart';
import 'data_table_card.dart';
import 'structured_view.dart';

/// What an agent gets when it declares a schema but names no component this
/// build knows — which is every agent a user writes themselves.
///
/// It reads the JSON rather than the schema, and makes three decisions:
/// a list of objects becomes a table of its own keys, a list of scalars
/// becomes a comma-separated line, and anything else becomes a labelled row.
/// No field names are assumed, so this works on data it has never seen.
class GenericDataView implements StructuredView {
  const GenericDataView();

  @override
  Widget build(BuildContext context, Map<String, dynamic> data) {
    final metrics = context.metrics;
    if (data.isEmpty) {
      return _Note(
        text: 'The model returned an empty result.',
        context: context,
      );
    }

    // Tables last: a screenful of rows between two one-line fields would bury
    // the second, and the scalars read as a summary of the tables anyway.
    final scalars = <MapEntry<String, dynamic>>[];
    final tables = <MapEntry<String, dynamic>>[];
    for (final entry in data.entries) {
      if (readObjectList(entry.value).isNotEmpty) {
        tables.add(entry);
      } else {
        scalars.add(entry);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final entry in scalars) ...<Widget>[
          _Field(name: entry.key, value: _describe(entry.value)),
          SizedBox(height: metrics.gapMd),
        ],
        for (final (index, entry) in tables.indexed) ...<Widget>[
          if (index > 0 || scalars.isNotEmpty) SizedBox(height: metrics.gapSm),
          MonoLabel(_label(entry.key), variant: MonoStyle.overline),
          SizedBox(height: metrics.gapSm),
          _Table(rows: readObjectList(entry.value)),
          SizedBox(height: metrics.gapMd),
        ],
      ],
    );
  }

  /// A scalar as one line. A list of scalars is joined rather than tabled —
  /// `rain_expected: Tokyo, Berlin` says more than a one-column table would.
  static String _describe(Object? value) => switch (value) {
    null => '',
    final List<Object?> list =>
      list
          .where((item) => item != null && item is! Map && item is! List)
          .join(', '),
    final Map<Object?, Object?> _ => '',
    _ => '$value',
  };

  /// `rain_expected` → `RAIN EXPECTED`.
  static String _label(String key) => key.replaceAll('_', ' ').toUpperCase();
}

/// A table of whatever keys the rows happen to carry.
class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    // The union of every row's keys, in first-seen order, so a row missing a
    // field still lines up under the right headings.
    final keys = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!keys.contains(key)) keys.add(key);
      }
    }

    return DataTableCard(
      columns: <DataField>[
        for (final key in keys)
          DataField(
            label: GenericDataView._label(key),
            numeric: rows.every((row) => row[key] == null || row[key] is num),
            cell: (row) => GenericDataView._describe(row[key]),
          ),
      ],
      rows: rows,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: MonoLabel(
            GenericDataView._label(name),
            variant: MonoStyle.overline,
            maxLines: 2,
          ),
        ),
        SizedBox(width: context.metrics.gapMd),
        Expanded(
          flex: 3,
          child: Text(
            value.isEmpty ? '—' : value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.context});

  final String text;
  final BuildContext context;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted),
  );
}
