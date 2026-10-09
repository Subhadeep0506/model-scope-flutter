import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/agent_run.dart';
import '../../data/repositories/agent_repository.dart';
import '../view_models/agent_run_state.dart';
import '../view_models/agent_run_view_model.dart';
import '../widgets/agent_inputs_card.dart';
import '../widgets/agent_log_sheet.dart';
import '../widgets/agent_model_picker.dart';
import '../widgets/agent_output_card.dart';
import '../widgets/agent_run_button.dart';
import '../widgets/agent_trace_list.dart';
import '../widgets/mono_label.dart';
import '../widgets/run_history_card.dart';
import '../widgets/section_card.dart';
import '../widgets/square_icon_button.dart';

/// One agent: what it does, what it needs, and what happened when it ran.
///
/// The configuration and the run share a screen, as the mockups draw them —
/// pressing Run collapses the description, model and input cards away so the
/// trace has the height, and the run button stays at the top as `Stop`.
class AgentDetailScreen extends ConsumerStatefulWidget {
  const AgentDetailScreen({super.key, required this.agentId});

  final String agentId;

  @override
  ConsumerState<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends ConsumerState<AgentDetailScreen> {
  /// Held in a field rather than read in [dispose]: `ref` leans on the
  /// `BuildContext`, which is gone by the time a widget is being unmounted.
  /// The provider is not auto-disposed, so the notifier outlives this screen.
  late final AgentRunViewModel _agent = ref.read(
    agentRunViewModelProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    // After the first frame, so the notifier is not written to while the
    // widget tree is still building.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _agent.open(widget.agentId),
    );
  }

  @override
  void dispose() {
    // Cancels a run still in flight, so leaving the screen — by the back
    // square, the system gesture or a tab switch — does not leave a stream
    // writing into a state nothing is drawing.
    _agent.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentRunViewModelProvider);
    final metrics = context.metrics;

    // Re-read the agent whenever the list changes. Only the builder changes
    // it, so this fires when the user has just saved an edit or reset a
    // built-in on the screen above — without it, popping back would show what
    // the agent used to be and run that instead. Never mid-run: the pipeline
    // in flight is the one already loaded.
    ref.listen(agentsProvider, (_, next) {
      if (next.isLoading || state.isRunning) return;
      _agent.open(widget.agentId);
    });

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
              child: _Header(state: state),
            ),
            Expanded(
              child: switch (state.status) {
                AgentRunStatus.loading => const Center(
                  child: CircularProgressIndicator(),
                ),
                AgentRunStatus.failed => _Note(
                  text: state.error ?? 'That agent could not be opened.',
                ),
                _ => _Body(state: state),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Back on the left, then the tool names in mono caps and the agent's name.
class _Header extends ConsumerWidget {
  const _Header({required this.state});

  final AgentRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final palette = context.palette;
    final template = state.agent?.template;
    final tools = template?.toolNames ?? const <String>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SquareIconButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back to the agent bench',
          borderColor: palette.outline,
          onPressed: () => _back(context, ref),
        ),
        SizedBox(width: metrics.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MonoLabel(
                tools.isEmpty
                    ? 'NO TOOLS'
                    : tools.map((tool) => tool.toUpperCase()).join('  ·  '),
                variant: MonoStyle.overline,
                maxLines: 2,
              ),
              const SizedBox(height: 2),
              Text(
                template?.name ?? 'Agent',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        if (state.agent case final agent?) _Menu(agent: agent),
      ],
    );
  }

  /// Back out of a looked-at run to the configuration first, so one tap does
  /// not leave the screen from two levels in.
  void _back(BuildContext context, WidgetRef ref) {
    if (state.viewing != null) {
      ref.read(agentRunViewModelProvider.notifier).backToIdle();
      return;
    }
    if (context.canPop()) context.pop();
  }
}

/// Where an agent is edited from.
///
/// Every agent can be edited, built-in or not. A built-in's own file is in the
/// bundle where nothing on the device can touch it, so `Edit agent` saves a
/// copy under the same id that shadows it — same card, same name, same run
/// history — and `Reset to built-in`, in the builder, throws that copy away.
/// `Duplicate` is still there for keeping the original alongside a variant.
class _Menu extends StatelessWidget {
  const _Menu({required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: Icon(Icons.more_vert_rounded, color: context.palette.muted),
    tooltip: 'More',
    onSelected: (value) => switch (value) {
      'edit' => context.push(Routes.agentEditOf(agent.id)),
      _ => context.push(Routes.agentCopyOf(agent.id)),
    },
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(value: 'edit', child: Text('Edit agent')),
      const PopupMenuItem<String>(
        value: 'copy',
        child: Text('Duplicate as a new agent'),
      ),
    ],
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final AgentRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final notifier = ref.read(agentRunViewModelProvider.notifier);
    final template = state.agent?.template;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        0,
        metrics.pagePadding,
        metrics.gapXl,
      ),
      children: <Widget>[
        if (!state.showsRun && template != null) ...<Widget>[
          if (template.description.isNotEmpty) ...<Widget>[
            _Description(state: state),
            SizedBox(height: metrics.gapMd),
          ],
          AgentModelPicker(
            models: state.installed,
            selectedId: state.modelId,
            onSelected: notifier.selectModel,
          ),
          SizedBox(height: metrics.gapMd),
          AgentInputsCard(
            inputs: template.inputs,
            values: state.values,
            expanded: state.inputsExpanded,
            enabled: !state.isRunning,
            onToggle: notifier.toggleInputs,
            onChanged: notifier.setValue,
          ),
          SizedBox(height: metrics.gapLg),
        ],
        if (state.viewing == null)
          AgentRunButton(
            isRunning: state.isRunning,
            isIndexing: state.status == AgentRunStatus.indexing,
            usesDefaults: state.usesDefaults,
            enabled: state.canRun && state.status != AgentRunStatus.blocked,
            onRun: notifier.run,
            onStop: notifier.stop,
          )
        else
          _RunAgain(onPressed: notifier.backToIdle),
        if (!state.showsRun && state.error != null) ...<Widget>[
          SizedBox(height: metrics.gapMd),
          _Blocker(text: state.error ?? ''),
        ],
        if (!state.showsRun)
          if (state.toolWarning case final warning?) ...<Widget>[
            SizedBox(height: metrics.gapMd),
            _Blocker(text: warning),
          ],
        if (state.notice case final notice?) ...<Widget>[
          SizedBox(height: metrics.gapMd),
          _Notice(text: notice),
        ],
        if (state.showsRun) ...<Widget>[
          SizedBox(height: metrics.gapXl),
          AgentTraceList(
            entries: state.visibleTrace,
            totalLabel: state.traceTotalLabel,
            isRunning: state.isRunning,
            onShowLogs: state.viewing != null
                ? null
                : () => AgentLogSheet.show(context, state.logs),
          ),
          SizedBox(height: metrics.gapXl),
          AgentOutputCard(
            text: state.visibleOutput,
            isStreaming: state.isRunning,
            isThinking: state.isThinking,
            error: state.viewing?.error ?? state.error,
            // A past run carries its own, recorded when it finished, so
            // editing the agent since cannot change how its history draws.
            isStructured: state.showsStructured,
            view: state.visibleView,
          ),
        ],
        if (!state.showsRun && state.history.isNotEmpty) ...<Widget>[
          SizedBox(height: metrics.gapXl),
          const MonoLabel('RUN HISTORY', variant: MonoStyle.overline),
          SizedBox(height: metrics.gapSm),
          _History(runs: state.history, onOpen: notifier.openRun),
        ],
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.state});

  final AgentRunState state;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final template = state.agent?.template;

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              template?.description ?? '',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.palette.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.runs, required this.onOpen});

  final List<AgentRun> runs;
  final void Function(AgentRun run) onOpen;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final now = DateTime.now();

    return Column(
      children: <Widget>[
        for (final (index, run) in runs.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: metrics.gapSm),
          RunHistoryCard(
            key: ValueKey<String>(run.id),
            run: run,
            now: now,
            onOpen: () => onOpen(run),
          ),
        ],
      ],
    );
  }
}

class _RunAgain extends StatelessWidget {
  const _RunAgain({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Run again'),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          side: BorderSide(color: palette.primary),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: context.metrics.controlShape,
          ),
        ),
      ),
    );
  }
}

/// Why the agent cannot run, in the amber the bench card uses for the same
/// line.
class _Blocker extends StatelessWidget {
  const _Blocker({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _Banner(
    text: text,
    icon: Icons.error_outline_rounded,
    colour: context.palette.warning,
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _Banner(
    text: text,
    icon: Icons.info_outline_rounded,
    colour: context.palette.muted,
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.icon, required this.colour});

  final String text;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: colour),
        SizedBox(width: metrics.gapSm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colour),
          ),
        ),
      ],
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
