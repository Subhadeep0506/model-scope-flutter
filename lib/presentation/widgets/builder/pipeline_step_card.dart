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
import 'reads_picker.dart';
import 'tool_picker_grid.dart';

/// One numbered step in the `Pipeline` section.
///
/// Draws what the mockups draw, less the per-step `MODEL` dropdown: every step
/// of a run uses the run's one model, so a control for it would do nothing.
/// It gains a prompt field on a tool step, which the mockups leave out and
/// every agent this build ships uses.
class PipelineStepCard extends ConsumerWidget {
  const PipelineStepCard({
    super.key,
    required this.step,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.available,
  });

  final DraftStep step;
  final int number;
  final bool isFirst;
  final bool isLast;

  /// What this step may read — inputs, and the steps above it.
  final List<DraftReference> available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);
    final isTool = step.kind == StepKind.tool;

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(step: step, number: number, isFirst: isFirst, isLast: isLast),
          SizedBox(height: metrics.gapMd),
          if (isTool) ...<Widget>[
            ToolPickerGrid(
              selected: step.tool,
              onSelected: (tool) => builder.setStepTool(step.key, tool),
            ),
            SizedBox(height: metrics.gapMd),
            BuilderField(
              value: step.prompt,
              hint:
                  'What to tell the model before it calls the tool '
                  '(optional)',
              maxLines: null,
              onChanged: (value) => builder.setStepPrompt(step.key, value),
            ),
          ] else
            BuilderField(
              value: step.prompt,
              hint: 'What should the model reason about?',
              maxLines: null,
              onChanged: (value) => builder.setStepPrompt(step.key, value),
            ),
          SizedBox(height: metrics.gapMd),
          ReadsPicker(
            available: available,
            selected: step.reads,
            onToggle: (reference) =>
                builder.toggleStepRead(step.key, reference),
          ),
          SizedBox(height: metrics.gapMd),
          Row(
            children: <Widget>[
              const MonoLabel('READ AS', variant: MonoStyle.overline),
              SizedBox(width: metrics.gapSm),
              Expanded(
                child: BuilderField(
                  value: step.id,
                  hint: 'step_id',
                  mono: true,
                  onChanged: (value) => builder.setStepId(step.key, value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.step,
    required this.number,
    required this.isFirst,
    required this.isLast,
  });

  final DraftStep step;
  final int number;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return Row(
      children: <Widget>[
        Container(
          padding: EdgeInsets.symmetric(horizontal: metrics.gapSm, vertical: 2),
          decoration: BoxDecoration(
            color: palette.fieldFill,
            borderRadius: metrics.controlShape,
          ),
          child: MonoLabel('$number', variant: MonoStyle.tag),
        ),
        SizedBox(width: metrics.gapSm),
        _KindToggle(step: step),
        const Spacer(),
        _Action(
          icon: Icons.arrow_upward_rounded,
          label: 'Move up',
          onPressed: isFirst ? null : () => builder.moveStep(step.key, -1),
        ),
        _Action(
          icon: Icons.arrow_downward_rounded,
          label: 'Move down',
          onPressed: isLast ? null : () => builder.moveStep(step.key, 1),
        ),
        _Action(
          icon: Icons.copy_rounded,
          label: 'Duplicate',
          onPressed: () => builder.duplicateStep(step.key),
        ),
        _Action(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onPressed: () => builder.removeStep(step.key),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;

  /// Null greys it out — the first step cannot move up.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    color: context.palette.muted,
    tooltip: label,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    padding: EdgeInsets.zero,
  );
}

/// The `Tool | Reason` pair.
class _KindToggle extends ConsumerWidget {
  const _KindToggle({required this.step});

  final DraftStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: context.palette.fieldFill,
        borderRadius: metrics.controlShape,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _KindOption(
            label: 'Tool',
            icon: Icons.build_outlined,
            selected: step.kind == StepKind.tool,
            onTap: () => builder.setStepKind(step.key, StepKind.tool),
          ),
          _KindOption(
            label: 'Reason',
            icon: Icons.psychology_outlined,
            selected: step.kind == StepKind.reason,
            onTap: () => builder.setStepKind(step.key, StepKind.reason),
          ),
        ],
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gapMd,
              vertical: metrics.gapSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? palette.onPrimary : palette.muted,
                ),
                SizedBox(width: metrics.gapXs + 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected ? palette.onPrimary : palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
