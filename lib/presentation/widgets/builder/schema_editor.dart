import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/view_models.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../domain/services/schema_fields.dart';
import '../../view_models/agent_builder_state.dart';
import '../mono_label.dart';
import 'labelled_field.dart';
import 'schema_field_row.dart';

/// The `Structured response` section: the `{} Fields` and `</> JSON schema`
/// tabs from `agents-new-agent-6.png` and `-7.png`.
///
/// The two are two views of one schema, and **either can be the source of
/// truth**. Normally the rows are, and the JSON is rendered from them. But a
/// schema can say things the rows cannot draw — an `enum`, a `$ref`, a
/// `minimum` — and simplifying one of those into what the rows understand
/// would change what the model is allowed to emit. So when the JSON cannot be
/// read back, it is kept as written and the Fields tab says so.
class SchemaEditor extends ConsumerStatefulWidget {
  const SchemaEditor({super.key, required this.answer});

  final DraftAnswer answer;

  @override
  ConsumerState<SchemaEditor> createState() => _SchemaEditorState();
}

class _SchemaEditorState extends ConsumerState<SchemaEditor> {
  bool _showJson = false;

  /// What the JSON tab holds while it is being typed into. Null means it has
  /// not been opened since the fields last changed, so it should be rendered
  /// fresh.
  String? _draftJson;

  /// Why the JSON will not be accepted, or null.
  String? _jsonError;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final answer = widget.answer;
    final fieldCount = _fieldCount(answer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toggle(
          isOn: answer.isStructured,
          caption: answer.isStructured
              ? 'Model must return JSON · $fieldCount '
                    '${fieldCount == 1 ? 'field' : 'fields'}'
              : 'The answer is written as prose',
          onChanged: (value) {
            ref
                .read(agentBuilderViewModelProvider.notifier)
                .setStructured(value);
            setState(() => _draftJson = null);
          },
        ),
        if (answer.isStructured) ...<Widget>[
          SizedBox(height: metrics.gapMd),
          _Tabs(
            showJson: _showJson,
            onChanged: (value) => setState(() {
              _showJson = value;
              // Rendered fresh each time it is opened, so it always shows
              // what the rows currently say.
              if (value) _draftJson = null;
              _jsonError = null;
            }),
          ),
          SizedBox(height: metrics.gapMd),
          if (_showJson) _json(context) else _fields(context),
        ],
      ],
    );
  }

  Widget _fields(BuildContext context) {
    final answer = widget.answer;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);
    final metrics = context.metrics;

    // Held as raw because the rows cannot draw it. Showing an empty or
    // simplified field list here would be a lie about what will be saved.
    if (answer.rawSchema != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BuilderWarning(
            text:
                'This schema uses something the field rows cannot show, so '
                'it is kept exactly as written. Edit it on the JSON tab.',
          ),
          SizedBox(height: metrics.gapMd),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () {
                builder.useFields();
                setState(() => _draftJson = null);
              },
              child: const Text('Replace it with fields'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final field in answer.fields)
          SchemaFieldRow(
            key: ObjectKey(field),
            field: field,
            onChanged: builder.touchFields,
            onRemove: () {
              answer.fields.remove(field);
              builder.touchFields();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              answer.fields.add(SchemaField());
              builder.touchFields();
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add field'),
          ),
        ),
      ],
    );
  }

  Widget _json(BuildContext context) {
    final metrics = context.metrics;
    final error = _jsonError;
    final text = _draftJson ?? _render();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.answer.rawSchema != null) ...<Widget>[
          // Said here as well as on the Fields tab: someone who has just
          // pressed `Use this schema` and been left on this tab should be
          // told it was accepted, and why it is staying put.
          BuilderWarning(
            text:
                'Kept exactly as written — it uses something the field '
                'rows cannot show, so this tab is the only view of it.',
          ),
          SizedBox(height: metrics.gapSm),
        ],
        BuilderField(
          // Keyed on the rendered text so reopening the tab after editing the
          // rows refreshes the box rather than showing what was there before.
          key: ValueKey<String>(text),
          value: text,
          maxLines: null,
          mono: true,
          hint: '{ "type": "object", … }',
          onChanged: (value) => _draftJson = value,
        ),
        if (error != null) ...<Widget>[
          SizedBox(height: metrics.gapSm),
          BuilderWarning(text: error),
        ],
        SizedBox(height: metrics.gapMd),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _applyJson,
            child: const Text('Use this schema'),
          ),
        ),
      ],
    );
  }

  /// The schema as it stands, indented to be read and edited.
  String _render() {
    final schema = widget.answer.toSchema();
    if (schema == null) return '';
    return const JsonEncoder.withIndent('  ').convert(schema);
  }

  void _applyJson() {
    final text = (_draftJson ?? _render()).trim();
    if (text.isEmpty) {
      setState(() => _jsonError = 'There is no schema here to use.');
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      // The text is left exactly as typed: losing someone's work because of a
      // missing comma would be the worst possible response to a typo.
      setState(() => _jsonError = 'That is not valid JSON. ${error.message}');
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      setState(
        () => _jsonError = 'A schema has to be a JSON object, starting with {.',
      );
      return;
    }

    ref.read(agentBuilderViewModelProvider.notifier).setRawSchema(decoded);
    setState(() {
      _jsonError = null;
      _draftJson = null;
      // Back to the rows when they can show it; staying on the JSON tab when
      // they cannot, since that is now the only honest view of it.
      _showJson = widget.answer.rawSchema != null;
    });
  }

  static int _fieldCount(DraftAnswer answer) {
    final schema = answer.toSchema();
    final properties = schema?['properties'];
    return properties is Map<String, dynamic> ? properties.length : 0;
  }
}

/// The `Structured response` switch and its caption.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.isOn,
    required this.caption,
    required this.onChanged,
  });

  final bool isOn;
  final String caption;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(metrics.gapMd),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: metrics.controlShape,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Structured response',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
          Switch(value: isOn, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.showJson, required this.onChanged});

  final bool showJson;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Container(
      decoration: BoxDecoration(
        color: context.palette.fieldFill,
        borderRadius: metrics.controlShape,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Tab(
              label: '{} Fields',
              selected: !showJson,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _Tab(
              label: '</> JSON schema',
              selected: showJson,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.primary : Colors.transparent,
        borderRadius: metrics.controlShape,
        child: InkWell(
          onTap: onTap,
          borderRadius: metrics.controlShape,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: metrics.gapMd),
            child: Center(
              child: MonoLabel(
                label,
                variant: MonoStyle.tag,
                color: selected ? palette.onPrimary : palette.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
