import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/di/view_models.dart';
import '../../../config/theme/app_metrics.dart';
import '../../../config/theme/app_palette.dart';
import '../../../data/models/agent_template.dart';
import '../../view_models/agent_builder_state.dart';
import '../labelled_slider.dart';
import '../section_card.dart';

/// How much text one run of this agent may push at the model.
///
/// Only the half that applies is drawn: the web rows need a step that searches
/// or fetches a page, the document rows a step that retrieves. An agent that
/// does neither gets no card at all, because six sliders controlling nothing
/// is worse than none.
class LimitsCard extends ConsumerWidget {
  const LimitsCard({super.key, required this.draft});

  final AgentDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);
    final limits = draft.limits;

    return SectionCard(
      padding: EdgeInsets.fromLTRB(
        metrics.gapLg,
        metrics.gapLg,
        metrics.gapLg,
        metrics.gapSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (draft.usesWebTools) ...<Widget>[
            const _Note(
              'What a search puts in front of the model. Fewer results, and '
              'shorter extracts, leave the model more room to think.',
            ),
            SizedBox(height: metrics.gapMd),
            _Row(
              label: 'WEB RESULTS',
              value: limits.webResults,
              range: AgentLimits.webResultsRange,
              step: 1,
              onChanged: builder.setWebResults,
            ),
            _Row(
              label: 'CHARS PER RESULT',
              value: limits.webSnippetChars,
              range: AgentLimits.webSnippetCharsRange,
              step: 80,
              onChanged: builder.setWebSnippetChars,
            ),
            _Row(
              label: 'CHARS PER PAGE',
              value: limits.webPageChars,
              range: AgentLimits.webPageCharsRange,
              step: 500,
              onChanged: builder.setWebPageChars,
            ),
          ],
          if (draft.usesWebTools && draft.usesDocumentTools)
            SizedBox(height: metrics.gapMd),
          if (draft.usesDocumentTools) ...<Widget>[
            const _Note(
              'How the document is split, and how much of it comes back per '
              'question. Changing the passage length re-indexes the document '
              'on the next run.',
            ),
            SizedBox(height: metrics.gapMd),
            _Row(
              label: 'PASSAGE LENGTH',
              value: limits.chunkChars,
              range: AgentLimits.chunkCharsRange,
              step: 100,
              onChanged: builder.setChunkChars,
            ),
            _Row(
              label: 'PASSAGE OVERLAP',
              value: limits.chunkOverlapChars,
              // Never more than half a passage: the chunker halves it anyway,
              // so a slider that went higher would appear to do nothing.
              range: (
                AgentLimits.chunkOverlapCharsRange.$1,
                _overlapCeiling(limits.chunkChars),
              ),
              step: 20,
              onChanged: builder.setChunkOverlapChars,
            ),
            _Row(
              label: 'PASSAGES RETRIEVED',
              value: limits.passages,
              range: AgentLimits.passagesRange,
              step: 1,
              onChanged: builder.setPassages,
            ),
          ],
        ],
      ),
    );
  }

  static int _overlapCeiling(int chunkChars) {
    final half = chunkChars ~/ 2;
    final ceiling = AgentLimits.chunkOverlapCharsRange.$2;
    return half < ceiling ? half : ceiling;
  }
}

/// One slider, in whole steps, writing to the draft as it moves.
///
/// Unlike the Runtime defaults card there is no local copy held while a thumb
/// is dragging: committing here costs a redraw, not a model reload.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.range,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final (int, int) range;

  /// How far one notch moves, which also decides the division count.
  final int step;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((range.$2 - range.$1) ~/ step).clamp(1, 200);

    return LabelledSlider(
      label: label,
      value: value.toDouble(),
      display: '$value',
      range: asDoubles(range),
      divisions: divisions,
      onChanged: (v) => onChanged(v.round()),
      onChangeEnd: (v) => onChanged(v.round()),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.palette.muted, height: 1.4),
  );
}
