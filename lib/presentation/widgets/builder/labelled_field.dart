import 'package:flutter/material.dart';

import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';

/// A text field that keeps its caret where the user left it.
///
/// Every field in the builder goes through this. A `TextField` fed straight
/// from state is rewritten on every keystroke, which sends the caret to the
/// end of the line — so the controller lives here and is only written to when
/// the value changed from somewhere other than this field. The same pattern
/// as `_Field` in `agent_inputs_card.dart`.
class BuilderField extends StatefulWidget {
  const BuilderField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.maxLines = 1,
    this.enabled = true,
    this.keyboardType,
    this.mono = false,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Drawn above the field. Null draws nothing, for a field in a row.
  final String? label;

  final String? hint;
  final int? maxLines;
  final bool enabled;
  final TextInputType? keyboardType;

  /// Monospace, for JSON and for anything that becomes an identifier.
  final bool mono;

  @override
  State<BuilderField> createState() => _BuilderFieldState();
}

class _BuilderFieldState extends State<BuilderField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(BuilderField old) {
    super.didUpdateWidget(old);
    // Only when something other than typing changed it — writing on every
    // keystroke would move the caret to the end of the line.
    if (widget.value != _controller.text && widget.value != old.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = context.metrics;
    final label = widget.label;

    final field = TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      style: widget.mono
          ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
          : theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        fillColor: context.palette.fieldFill,
      ),
    );

    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodyMedium),
        SizedBox(height: metrics.gapXs + 2),
        field,
      ],
    );
  }
}

/// The `Basics` / `Inputs` / `Pipeline` headings, with an optional action on
/// the right — `+ Input`, as the mockups draw it.
class BuilderSection extends StatelessWidget {
  const BuilderSection({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ?action,
          ],
        ),
        SizedBox(height: metrics.gapMd),
        child,
      ],
    );
  }
}

/// The amber line a step shows when the tool it names cannot run yet.
class BuilderWarning extends StatelessWidget {
  const BuilderWarning({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gapMd,
        vertical: metrics.gapSm,
      ),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        borderRadius: metrics.controlShape,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 15, color: palette.warning),
          SizedBox(width: metrics.gapSm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.warning),
            ),
          ),
        ],
      ),
    );
  }
}
