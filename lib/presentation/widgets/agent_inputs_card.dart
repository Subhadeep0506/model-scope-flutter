import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/agent_template.dart';
import 'section_card.dart';

/// The `Configure inputs` expander and the fields inside it.
///
/// Collapsed to start with, because the common case is `Run with defaults` —
/// every bundled agent ships with values that work. Opening it is what turns
/// the run button into `Run configured`.
class AgentInputsCard extends StatelessWidget {
  const AgentInputsCard({
    super.key,
    required this.inputs,
    required this.values,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.onChanged,
  });

  final List<AgentInput> inputs;

  /// What each input currently holds, by input name.
  final Map<String, String> values;

  final bool expanded;

  /// False while a run is going, so the fields cannot be edited underneath it.
  final bool enabled;

  final VoidCallback onToggle;
  final void Function(String name, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Column(
      children: <Widget>[
        SectionCard(
          onTap: inputs.isEmpty ? null : onToggle,
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gapLg,
            vertical: metrics.gapLg,
          ),
          child: _Header(
            expanded: expanded,
            subtitle: inputs.isEmpty ? 'This agent takes no inputs' : null,
          ),
        ),
        if (expanded && inputs.isNotEmpty) ...<Widget>[
          SizedBox(height: metrics.gapSm),
          SectionCard(
            padding: EdgeInsets.all(metrics.gapLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final (index, input) in inputs.indexed) ...<Widget>[
                  if (index > 0) SizedBox(height: metrics.gapLg),
                  _Field(
                    input: input,
                    value: values[input.name] ?? '',
                    enabled: enabled,
                    onChanged: (value) => onChanged(input.name, value),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.expanded, this.subtitle});

  final bool expanded;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;
    final caption = subtitle;

    return Row(
      children: <Widget>[
        Icon(Icons.tune_rounded, size: 18, color: palette.primary),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: Text(
            'Configure inputs',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (caption != null)
          Text(caption, style: Theme.of(context).textTheme.bodySmall)
        else
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: palette.muted,
          ),
      ],
    );
  }
}

/// One labelled field. A choice is a dropdown, a number gets the numeric
/// keyboard, and a file is a plain path box — nothing in this build consumes
/// a file, so there is nothing to open a picker for yet.
class _Field extends StatefulWidget {
  const _Field({
    required this.input,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AgentInput input;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    // Only when something other than typing changed it — writing the value
    // back on every keystroke would move the caret to the end of the line.
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
    final input = widget.input;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(input.label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        if (input.type == AgentInputType.choice && input.options.isNotEmpty)
          _Choice(
            input: input,
            value: widget.value,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
          )
        else
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            keyboardType: input.type == AgentInputType.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            inputFormatters: input.type == AgentInputType.number
                ? <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ]
                : null,
            maxLines: input.type == AgentInputType.text ? null : 1,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: input.required ? null : 'Optional',
              isDense: true,
            ),
          ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.input,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AgentInput input;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.gapMd),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: metrics.controlShape,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: input.options.contains(value) ? value : input.options.first,
          isExpanded: true,
          isDense: true,
          borderRadius: metrics.cardShape,
          style: Theme.of(context).textTheme.bodyMedium,
          items: <DropdownMenuItem<String>>[
            for (final option in input.options)
              DropdownMenuItem<String>(value: option, child: Text(option)),
          ],
          onChanged: enabled
              ? (option) => option == null ? null : onChanged(option)
              : null,
        ),
      ),
    );
  }
}
