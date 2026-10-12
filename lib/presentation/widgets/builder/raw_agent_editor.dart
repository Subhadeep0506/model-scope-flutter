import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/view_models.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../data/models/agent_template.dart';
import '../../view_models/agent_builder_state.dart';
import '../../view_models/agent_builder_view_model.dart';
import '../mono_label.dart';
import '../square_icon_button.dart';
import 'labelled_field.dart';

class RawAgentEditor extends ConsumerStatefulWidget {
  const RawAgentEditor({super.key, required this.draft});

  final AgentDraft draft;

  @override
  ConsumerState<RawAgentEditor> createState() => _RawAgentEditorState();
}

class _RawAgentEditorState extends ConsumerState<RawAgentEditor> {
  late String _text = _render();
  String? _error;
  bool _saving = false;

  String _render() {
    final template = widget.draft.toTemplate(
      id: widget.draft.id ?? 'new_agent',
      createdAt: widget.draft.createdAt ?? DateTime.now(),
    );
    return const JsonEncoder.withIndent('  ').convert(template.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                metrics.gapLg,
                metrics.pagePadding,
                metrics.gapLg,
              ),
              child: Row(
                children: <Widget>[
                  SquareIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back to the builder',
                    borderColor: palette.outline,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  SizedBox(width: metrics.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const MonoLabel(
                          'THE WHOLE AGENT',
                          variant: MonoStyle.overline,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Edit as JSON',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
                children: <Widget>[
                  BuilderField(
                    value: _text,
                    maxLines: null,
                    mono: true,
                    onChanged: (value) => _text = value,
                  ),
                  if (error != null) ...<Widget>[
                    SizedBox(height: metrics.gapMd),
                    BuilderWarning(text: error),
                  ],
                  SizedBox(height: metrics.gapXl),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                metrics.gapSm,
                metrics.pagePadding,
                metrics.gapMd,
              ),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: metrics.controlShape,
                  ),
                ),
                child: const Text('Save agent'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final template = _parse();
    if (template == null) return;

    setState(() => _saving = true);
    final outcome = await ref
        .read(agentBuilderViewModelProvider.notifier)
        .saveTemplate(template);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (outcome) {
      case SaveSucceeded():
        messenger.showSnackBar(const SnackBar(content: Text('Agent saved.')));
        navigator.pop(true);
      case SaveRejected(:final problems):
        setState(() => _error = problems.join('\n'));
      case SaveFailed(:final reason):
        setState(() => _error = reason);
    }
  }

  AgentTemplate? _parse() {
    final Object? decoded;
    try {
      decoded = jsonDecode(_text);
    } on FormatException catch (error) {
      setState(() => _error = 'That is not valid JSON. ${error.message}');
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      setState(() => _error = 'An agent has to be a JSON object.');
      return null;
    }

    try {
      final template = AgentTemplate.fromJson(decoded);
      if (template.id.trim().isEmpty) {
        setState(() => _error = 'This agent needs an "id" to be saved under.');
        return null;
      }
      setState(() => _error = null);
      return template;
    } catch (error) {
      setState(
        () => _error =
            'That is not an agent this build can read.\n'
            '$error',
      );
      return null;
    }
  }
}
