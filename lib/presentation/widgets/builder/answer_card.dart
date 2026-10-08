import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/view_models.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../view_models/agent_builder_state.dart';
import '../mono_label.dart';
import '../section_card.dart';
import '../structured/structured_view.dart';
import 'labelled_field.dart';
import 'reads_picker.dart';
import 'schema_editor.dart';

/// The `Answer · always last` card.
///
/// Carries a prompt field the mockups leave out — `answer.prompt` is required
/// and is the question the final step actually asks, so an agent cannot be
/// built without one. It also carries the `view` picker, which the mockups
/// have no equivalent for because they predate structured responses having
/// components to draw them.
class AnswerCard extends ConsumerWidget {
  const AnswerCard({super.key, required this.answer, required this.available});

  final DraftAnswer answer;

  /// Everything the answer may read: every input and every step.
  final List<DraftReference> available;

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
              Icon(Icons.flag_outlined, size: 18, color: palette.primary),
              SizedBox(width: metrics.gapSm),
              // Expanded so the title wraps rather than runs off the card at
              // a large system text size.
              Expanded(
                child: Text(
                  'Answer · always last',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.gapMd),
          BuilderField(
            value: answer.prompt,
            hint: 'What to ask for, using what the steps produced',
            maxLines: null,
            onChanged: builder.setAnswerPrompt,
          ),
          SizedBox(height: metrics.gapMd),
          ReadsPicker(
            available: available,
            selected: answer.reads,
            onToggle: builder.toggleAnswerRead,
          ),
          SizedBox(height: metrics.gapSm),
          Text(
            // Worth saying: an empty list is not an empty answer, and someone
            // ticking nothing should know what they will get.
            'Reading nothing hands the answer every step, in order.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
          SizedBox(height: metrics.gapLg),
          SchemaEditor(answer: answer),
          if (answer.isStructured) ...<Widget>[
            SizedBox(height: metrics.gapLg),
            _ViewPicker(answer: answer),
          ],
        ],
      ),
    );
  }
}

/// Which component draws the result.
class _ViewPicker extends ConsumerWidget {
  const _ViewPicker({required this.answer});

  final DraftAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);
    final current = answer.view;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const MonoLabel('DRAWN AS', variant: MonoStyle.overline),
        SizedBox(height: metrics.gapSm),
        Container(
          padding: EdgeInsets.symmetric(horizontal: metrics.gapMd),
          decoration: BoxDecoration(
            color: palette.fieldFill,
            borderRadius: metrics.controlShape,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              // An agent loaded from a file may name a component this build
              // does not have; it is listed rather than silently reset.
              value: current != null && !isKnownView(current) ? null : current,
              isExpanded: true,
              isDense: true,
              borderRadius: metrics.cardShape,
              style: Theme.of(context).textTheme.bodyMedium,
              hint: const Text('A plain table'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(child: Text('A plain table')),
                for (final view in knownViews)
                  DropdownMenuItem<String>(
                    value: view.name,
                    child: Text(view.label),
                  ),
              ],
              onChanged: builder.setView,
            ),
          ),
        ),
        if (current != null && !isKnownView(current)) ...<Widget>[
          SizedBox(height: metrics.gapSm),
          Text(
            'This agent names "$current", which this build has no component '
            'for. It will be drawn as a plain table.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
        ],
      ],
    );
  }
}
