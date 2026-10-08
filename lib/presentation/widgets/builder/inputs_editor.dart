import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/view_models.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../data/models/agent_template.dart';
import '../../view_models/agent_builder_state.dart';
import '../mono_label.dart';
import '../section_card.dart';
import 'labelled_field.dart';

/// The `Inputs` section: what the user is asked for before a run.
class InputsEditor extends ConsumerWidget {
  const InputsEditor({super.key, required this.inputs});

  final List<DraftInput> inputs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;

    if (inputs.isEmpty) {
      return Text(
        'No inputs. The agent will run on its prompts alone.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.palette.muted),
      );
    }

    return Column(
      children: <Widget>[
        for (final (index, input) in inputs.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: metrics.gapMd),
          _InputCard(key: ValueKey<String>(input.key), input: input),
        ],
      ],
    );
  }
}

class _InputCard extends ConsumerWidget {
  const _InputCard({super.key, required this.input});

  final DraftInput input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: BuilderField(
                  value: input.label,
                  hint: 'Label',
                  onChanged: (value) => builder.setInputLabel(input.key, value),
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Expanded(
                flex: 2,
                child: _TypeDropdown(
                  value: input.type,
                  onChanged: (type) => builder.setInputType(input.key, type),
                ),
              ),
              SizedBox(width: metrics.gapXs),
              IconButton(
                onPressed: () => builder.removeInput(input.key),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: palette.muted,
                tooltip: 'Remove this input',
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          // The name is what a prompt writes as `{{input.x}}`, so it is shown
          // rather than hidden — a step reading the wrong one is a confusing
          // failure to work backwards from.
          Row(
            children: <Widget>[
              const MonoLabel('READ AS', variant: MonoStyle.overline),
              SizedBox(width: metrics.gapSm),
              Expanded(
                child: BuilderField(
                  value: input.name,
                  hint: 'name',
                  mono: true,
                  onChanged: (value) => builder.setInputName(input.key, value),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.gapSm),
          if (input.type == AgentInputType.choice)
            _Options(input: input)
          else
            BuilderField(
              value: input.defaultValue,
              hint: 'Default value (optional)',
              keyboardType: input.type == AgentInputType.number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              onChanged: (value) => builder.setInputDefault(input.key, value),
            ),
          SizedBox(height: metrics.gapSm),
          _RequiredToggle(input: input),
        ],
      ),
    );
  }
}

/// The choices a `Choice` input offers, and which one it starts on.
///
/// Shown only for a choice, because the validator rejects one with no options
/// — so the editor appears the moment the type is picked rather than leaving
/// the user to find out on save.
class _Options extends ConsumerWidget {
  const _Options({required this.input});

  final DraftInput input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const MonoLabel('OPTIONS', variant: MonoStyle.overline),
        SizedBox(height: metrics.gapSm),
        for (final (index, option) in input.options.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: metrics.gapSm),
          Row(
            children: <Widget>[
              Expanded(
                child: BuilderField(
                  key: ValueKey<String>('${input.key}-$index'),
                  value: option,
                  hint: 'Option ${index + 1}',
                  onChanged: (value) =>
                      builder.setInputOption(input.key, index, value),
                ),
              ),
              IconButton(
                onPressed: () => builder.removeInputOption(input.key, index),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: context.palette.muted,
                tooltip: 'Remove this option',
              ),
            ],
          ),
        ],
        SizedBox(height: metrics.gapSm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => builder.addInputOption(input.key),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add option'),
          ),
        ),
        SizedBox(height: metrics.gapSm),
        BuilderField(
          value: input.defaultValue,
          hint: 'Which option it starts on (optional)',
          onChanged: (value) => builder.setInputDefault(input.key, value),
        ),
      ],
    );
  }
}

class _RequiredToggle extends ConsumerWidget {
  const _RequiredToggle({required this.input});

  final DraftInput input;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: <Widget>[
      Expanded(
        child: Text('Required', style: Theme.of(context).textTheme.bodyMedium),
      ),
      Switch(
        value: input.required,
        onChanged: (value) => ref
            .read(agentBuilderViewModelProvider.notifier)
            .setInputRequired(input.key, value),
      ),
    ],
  );
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({required this.value, required this.onChanged});

  final AgentInputType value;
  final ValueChanged<AgentInputType> onChanged;

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
        child: DropdownButton<AgentInputType>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: metrics.cardShape,
          style: Theme.of(context).textTheme.bodyMedium,
          items: <DropdownMenuItem<AgentInputType>>[
            for (final type in AgentInputType.values)
              DropdownMenuItem<AgentInputType>(
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
