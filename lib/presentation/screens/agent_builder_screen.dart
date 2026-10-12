import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/view_models.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../view_models/agent_builder_state.dart';
import '../view_models/agent_builder_view_model.dart';
import '../widgets/agent_icon.dart';
import '../widgets/builder/answer_card.dart';
import '../widgets/builder/inputs_editor.dart';
import '../widgets/builder/labelled_field.dart';
import '../widgets/builder/limits_card.dart';
import '../widgets/builder/pipeline_step_card.dart';
import '../widgets/builder/raw_agent_editor.dart';
import '../widgets/mono_label.dart';
import '../widgets/section_card.dart';
import '../widgets/square_icon_button.dart';

/// The pipeline builder: a whole agent on one screen.
class AgentBuilderScreen extends ConsumerStatefulWidget {
  const AgentBuilderScreen({super.key, this.agentId, this.duplicate = false});
  final String? agentId;
  final bool duplicate;

  @override
  ConsumerState<AgentBuilderScreen> createState() => _AgentBuilderScreenState();
}

class _AgentBuilderScreenState extends ConsumerState<AgentBuilderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(agentBuilderViewModelProvider.notifier)
          .open(agentId: widget.agentId, duplicate: widget.duplicate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentBuilderViewModelProvider);
    final metrics = context.metrics;

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
              child: _Header(
                isEditing: widget.agentId != null && !widget.duplicate,
                isBuiltIn: ref
                    .watch(agentBuilderViewModelProvider.notifier)
                    .isBuiltInOverride,
                onDelete: _confirmDelete,
                onEditJson: _editJson,
              ),
            ),
            Expanded(
              child: switch (state) {
                AsyncError(:final error) => _Note(text: '$error'),
                AsyncLoading() when !state.hasValue => const Center(
                  child: CircularProgressIndicator(),
                ),
                _ => _Form(draft: state.value ?? AgentDraft()),
              },
            ),
            if (state.hasValue) _SaveBar(onSave: _save),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(agentBuilderViewModelProvider.notifier)
        .save();
    if (!mounted) return;

    switch (outcome) {
      case SaveSucceeded():
        messenger.showSnackBar(const SnackBar(content: Text('Agent saved.')));
        await navigator.maybePop();
      case SaveRejected(:final problems):
        await _showProblems(problems);
      case SaveFailed(:final reason):
        await _showProblems(<String>[reason]);
    }
  }

  /// Everything wrong with the agent, in the validator's own words.
  Future<void> _showProblems(List<String> problems) => showModalBottomSheet(
    context: context,
    backgroundColor: context.palette.surface,
    builder: (context) => _ProblemSheet(problems: problems),
  );

  Future<void> _editJson() async {
    final draft = ref.read(agentBuilderViewModelProvider).value;
    if (draft == null) return;

    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(builder: (_) => RawAgentEditor(draft: draft)),
    );
    if ((saved ?? false) && mounted) await navigator.maybePop();
  }

  /// Deleting an agent the user built, or resetting an edited built-in.
  Future<void> _confirmDelete() async {
    final builder = ref.read(agentBuilderViewModelProvider.notifier);
    final isBuiltIn = builder.isBuiltInOverride;
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isBuiltIn ? 'Reset to the built-in?' : 'Delete this agent?',
        ),
        content: Text(
          isBuiltIn
              ? 'Your changes are thrown away and the version shipped with '
                    'the app comes back. Runs already recorded are kept.'
              : 'Its file is removed. Runs already recorded are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: Text(isBuiltIn ? 'Reset' : 'Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    isBuiltIn ? await builder.reset() : await builder.delete();
    if (!mounted) return;
    await navigator.maybePop();
    if (!isBuiltIn && mounted) await navigator.maybePop();
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.draft});
  final AgentDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.gapXl,
      ),
      children: <Widget>[
        BuilderSection(
          title: 'Basics',
          child: _Basics(draft: draft),
        ),
        SizedBox(height: metrics.gapXl),
        BuilderSection(
          title: 'System prompt',
          child: SectionCard(
            padding: EdgeInsets.all(metrics.gapMd),
            child: BuilderField(
              value: draft.systemPrompt,
              hint: 'How the model should behave for every step',
              maxLines: null,
              onChanged: builder.setSystemPrompt,
            ),
          ),
        ),
        SizedBox(height: metrics.gapXl),
        BuilderSection(
          title: 'Inputs',
          action: TextButton.icon(
            onPressed: builder.addInput,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Input'),
          ),
          child: InputsEditor(inputs: draft.inputs),
        ),
        SizedBox(height: metrics.gapXl),
        BuilderSection(
          title: 'Pipeline',
          child: _Pipeline(draft: draft),
        ),
        if (draft.usesWebTools || draft.usesDocumentTools) ...<Widget>[
          SizedBox(height: metrics.gapXl),
          BuilderSection(
            title: 'Limits',
            child: LimitsCard(draft: draft),
          ),
        ],
        SizedBox(height: metrics.gapMd),
        AnswerCard(
          answer: draft.answer,
          available: draft.referencesBefore(draft.steps.length),
        ),
      ],
    );
  }
}

class _Pipeline extends ConsumerWidget {
  const _Pipeline({required this.draft});
  final AgentDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, step) in draft.steps.indexed) ...<Widget>[
          PipelineStepCard(
            key: ValueKey<String>(step.key),
            step: step,
            number: index + 1,
            isFirst: index == 0,
            isLast: index == draft.steps.length - 1,
            available: draft.referencesBefore(index),
          ),
          SizedBox(height: metrics.gapMd),
        ],
        OutlinedButton.icon(
          onPressed: builder.addStep,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add step'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

class _Basics extends ConsumerWidget {
  const _Basics({required this.draft});
  final AgentDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final builder = ref.read(agentBuilderViewModelProvider.notifier);

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BuilderField(
            label: 'Name',
            value: draft.name,
            hint: 'e.g. News digest',
            onChanged: builder.setName,
          ),
          SizedBox(height: metrics.gapMd),
          BuilderField(
            label: 'Purpose',
            value: draft.purpose,
            hint: 'One line about what it tests',
            onChanged: builder.setPurpose,
          ),
          SizedBox(height: metrics.gapMd),
          Text('Icon', style: Theme.of(context).textTheme.bodyMedium),
          SizedBox(height: metrics.gapSm),
          _IconRow(selected: draft.icon, onSelected: builder.setIcon),
        ],
      ),
    );
  }
}

/// Every icon token the app can draw.
class _IconRow extends StatelessWidget {
  const _IconRow({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Wrap(
      spacing: metrics.gapSm,
      runSpacing: metrics.gapSm,
      children: <Widget>[
        for (final token in agentIconTokens)
          Semantics(
            selected: token == selected,
            button: true,
            child: Tooltip(
              message: token,
              child: Material(
                color: token == selected ? palette.pill : palette.fieldFill,
                borderRadius: metrics.controlShape,
                child: InkWell(
                  onTap: () => onSelected(token),
                  borderRadius: metrics.controlShape,
                  child: Container(
                    width: 48,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: metrics.controlShape,
                      border: Border.all(
                        color: token == selected
                            ? palette.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      agentIconFor(token),
                      size: 19,
                      color: token == selected
                          ? palette.primary
                          : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isEditing,
    required this.isBuiltIn,
    required this.onDelete,
    required this.onEditJson,
  });

  final bool isEditing;
  final bool isBuiltIn;
  final VoidCallback onDelete;
  final VoidCallback onEditJson;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SquareIconButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to the agent bench',
          borderColor: palette.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const MonoLabel('PIPELINE BUILDER', variant: MonoStyle.overline),
              const SizedBox(height: 2),
              Text(
                isEditing ? 'Edit agent' : 'New agent',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: palette.muted),
          tooltip: 'More',
          onSelected: (value) => value == 'json' ? onEditJson() : onDelete(),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'json',
              child: Text('Edit as JSON'),
            ),
            if (isEditing)
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(isBuiltIn ? 'Reset to built-in' : 'Delete agent'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SaveBar extends ConsumerWidget {
  const _SaveBar({required this.onSave});

  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final isEditing =
        ref.watch(agentBuilderViewModelProvider.notifier).mode ==
        BuilderMode.edit;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapSm,
        metrics.pagePadding,
        metrics.gapMd,
      ),
      child: FilledButton(
        onPressed: onSave,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: context.metrics.controlShape,
          ),
        ),
        child: Text(isEditing ? 'Save changes' : 'Create agent'),
      ),
    );
  }
}

/// What stopped the agent being saved.
class _ProblemSheet extends StatelessWidget {
  const _ProblemSheet({required this.problems});
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(metrics.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              problems.length == 1
                  ? 'One thing to fix'
                  : '${problems.length} things to fix',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: metrics.gapMd),
            for (final problem in problems)
              Padding(
                padding: EdgeInsets.only(bottom: metrics.gapSm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: palette.warning,
                    ),
                    SizedBox(width: metrics.gapSm),
                    Expanded(
                      child: Text(
                        problem,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(context.metrics.pagePadding),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );
}
