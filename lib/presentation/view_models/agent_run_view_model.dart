import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/model_descriptor.dart';
import '../../domain/services/agent_runner.dart';
import '../../domain/services/model_loader.dart';
import 'agent_run_state.dart';

/// Drives one agent's detail screen, including the run itself.
///
/// Holds the open agent directly rather than keying by id: one agent screen is
/// open at a time, and that also keeps this and the single loaded model in
/// step — the same arrangement [ChatViewModel] uses.
///
/// The weights are loaded here and nowhere else in this flow. Opening the
/// screen loads nothing; pressing Run loads, and the end of the run releases
/// the model again, so an agent never leaves its system prompt or its tools
/// sitting on a model that Chat is about to pick up.
class AgentRunViewModel extends Notifier<AgentRunState> {
  static const String _logName = 'AgentRunViewModel';

  StreamSubscription<AgentEvent>? _events;

  /// Kept so a stopped run can be recorded with the time it actually took —
  /// the runner's own record never arrives when the stream is cancelled.
  Stopwatch? _clock;
  DateTime? _startedAt;

  @override
  AgentRunState build() {
    ref.onDispose(() => _events?.cancel());
    return const AgentRunState();
  }

  /// Reads the agent, its history and the installed models. Loads no weights.
  Future<void> open(String agentId) async {
    state = const AgentRunState();
    try {
      final agent = await ref.read(agentRepositoryProvider).byId(agentId);
      if (agent == null) {
        state = const AgentRunState(
          status: AgentRunStatus.failed,
          error: 'That agent no longer exists.',
        );
        return;
      }

      final library = await ref.read(modelLibraryViewModelProvider.future);
      final runs = await ref.read(agentRunsProvider.future);
      final availability = await ref
          .read(agentValidatorProvider)
          .check(
            agent.template,
            hasModel: library.models.isNotEmpty,
            values: agent.template.defaultValues,
          );

      state = AgentRunState(
        agent: agent,
        status: availability.canRun
            ? AgentRunStatus.idle
            : AgentRunStatus.blocked,
        values: Map<String, String>.of(agent.template.defaultValues),
        modelId: library.activeId,
        installed: library.models,
        error: availability.firstBlocker,
        history: <AgentRun>[
          for (final run in runs)
            if (run.agentId == agentId) run,
        ],
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not open agent $agentId',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      state = AgentRunState(
        status: AgentRunStatus.failed,
        error: 'Could not open that agent: $error',
      );
    }
  }

  void setValue(String name, String value) => state = state.copyWith(
    values: <String, String>{...state.values, name: value},
  );

  void selectModel(String id) => state = state.copyWith(modelId: id);

  void toggleInputs() =>
      state = state.copyWith(inputsExpanded: !state.inputsExpanded);

  /// Opens a past run from `RUN HISTORY`, read-only.
  void openRun(AgentRun run) => state = state.copyWith(viewing: run);

  /// Back from a finished or looked-back-at run to the configuration.
  void backToIdle() => state = state.copyWith(
    status: AgentRunStatus.idle,
    trace: const <TraceEntry>[],
    logs: const <AgentLogEntry>[],
    output: '',
    clearViewing: true,
    clearNotice: true,
    clearError: true,
  );

  /// Loads the model, then walks the pipeline.
  Future<void> run() async {
    final agent = state.agent;
    if (agent == null || state.isRunning) return;

    final model = _modelToRun();
    if (model == null) {
      state = state.copyWith(
        status: AgentRunStatus.blocked,
        error: 'No model installed — download one in Settings',
      );
      return;
    }

    state = state.copyWith(
      status: AgentRunStatus.preparing,
      trace: const <TraceEntry>[],
      logs: const <AgentLogEntry>[],
      output: '',
      clearViewing: true,
      clearNotice: true,
      clearError: true,
    );
    _append('load', 'Loading ${model.name} from ${model.localPath}');

    final notice = await _loadWeights(model);
    if (state.status != AgentRunStatus.preparing) return;
    state = state.copyWith(notice: notice, clearNotice: notice == null);
    _append('load', notice ?? 'Loaded ${model.name}');

    _clock = Stopwatch()..start();
    _startedAt = DateTime.now();
    state = state.copyWith(status: AgentRunStatus.running);

    _events = ref
        .read(agentRunnerProvider)
        .run(agent.template, values: state.values, modelId: model.id)
        .listen(_onEvent, onError: _onStreamError);
  }

  /// Asks the model to stop and records what the run managed before it did.
  Future<void> stop() async {
    if (!state.isRunning) return;
    ref.read(llmServiceProvider).stop();
    await _events?.cancel();
    _events = null;
    _append('done', 'Stopped by the user.', isError: true);
    await _finish(_recordOf(error: 'Stopped before it finished.'));
  }

  /// Drops the open agent, stopping a run that is still going.
  ///
  /// Not awaited — this is called from the screen being disposed, which cannot
  /// wait. [_abandon] runs as far as its first await before the state is
  /// cleared, so it records the run it is ending rather than an empty one.
  void close() {
    if (_events != null) unawaited(_abandon());
    state = const AgentRunState();
  }

  /// Ends a run the user walked away from.
  ///
  /// The weights matter more than the record here: left loaded they would
  /// still carry this agent's system prompt and its tools, and Chat — which
  /// only reloads when the model *id* changes — would answer the next question
  /// as the agent. So the model is released whatever else happens.
  Future<void> _abandon() async {
    final run = _recordOf(error: 'Stopped before it finished.');
    ref.read(llmServiceProvider).stop();
    await _events?.cancel();
    _events = null;
    await ref.read(agentRunRepositoryProvider).add(run);
    ref.invalidate(agentRunsProvider);
    await ref.read(llmServiceProvider).dispose();
  }

  /// The model this run uses: the one picked on screen, or the active one.
  ModelDescriptor? _modelToRun() {
    final chosen = state.modelId;
    for (final model in state.installed) {
      if (model.id == chosen) return model;
    }
    return state.installed.isEmpty ? null : state.installed.first;
  }

  Future<String?> _loadWeights(ModelDescriptor model) async {
    try {
      final library = await ref.read(modelLibraryViewModelProvider.future);
      return await loadWithFallback(
        llm: ref.read(llmServiceProvider),
        model: model,
        settings: await ref.read(samplerViewModelProvider.future),
        runtime: await ref.read(appSettingsViewModelProvider.future),
        projectorPath: library.projectorFor(model.repoId)?.localPath,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not load the model for an agent run',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      _append('error', '$error', isError: true);
      state = state.copyWith(status: AgentRunStatus.finished, error: '$error');
      return null;
    }
  }

  void _onEvent(AgentEvent event) {
    switch (event) {
      case TraceAdded(:final entry):
        state = state.copyWith(trace: <TraceEntry>[...state.trace, entry]);
      case AnswerToken(:final text):
        state = state.copyWith(output: state.output + text);
      case LogAdded(:final entry):
        state = state.copyWith(logs: <AgentLogEntry>[...state.logs, entry]);
      case RunFinished(:final run):
        unawaited(_finish(run));
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    developer.log(
      'An agent run failed',
      name: _logName,
      error: error,
      stackTrace: stackTrace,
    );
    _append('error', '$error', isError: true);
    unawaited(_finish(_recordOf(error: '$error')));
  }

  /// Saves the run, refreshes everything that counts runs, and releases the
  /// model — the weights are held only for as long as a run needs them.
  Future<void> _finish(AgentRun run) async {
    _events = null;
    _clock?.stop();
    state = state.copyWith(
      status: AgentRunStatus.finished,
      trace: run.trace.isEmpty ? state.trace : run.trace,
      output: run.output.isEmpty ? state.output : run.output,
      error: run.error,
      clearError: run.error == null,
      history: <AgentRun>[run, ...state.history],
    );
    _append('done', run.error ?? 'Finished in ${run.durationMs}ms');

    await ref.read(agentRunRepositoryProvider).add(run);
    ref.invalidate(agentRunsProvider);
    await ref.read(llmServiceProvider).dispose();
  }

  /// A record built here rather than by the runner, for the two endings the
  /// runner never reaches: the user stopping it, and the stream erroring.
  AgentRun _recordOf({required String error}) {
    final agent = state.agent;
    final startedAt = _startedAt ?? DateTime.now();
    return AgentRun(
      id: '${agent?.id ?? 'agent'}-${startedAt.microsecondsSinceEpoch}',
      agentId: agent?.id ?? '',
      agentName: agent?.template.name ?? '',
      modelId: _modelToRun()?.id ?? '',
      startedAt: startedAt,
      durationMs: _clock?.elapsedMilliseconds ?? 0,
      trace: state.trace,
      output: state.output,
      error: error,
    );
  }

  void _append(String channel, String text, {bool isError = false}) =>
      state = state.copyWith(
        logs: <AgentLogEntry>[
          ...state.logs,
          AgentLogEntry(
            at: DateTime.now(),
            channel: channel,
            text: text,
            isError: isError,
          ),
        ],
      );
}
