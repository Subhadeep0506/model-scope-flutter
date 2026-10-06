import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/agent_template.dart';
import '../../data/models/catalog_model.dart';
import '../../data/models/model_descriptor.dart';
import '../../domain/services/agent_runner.dart';
import '../../domain/services/model_loader.dart';
import 'agent_run_state.dart';

class AgentRunViewModel extends Notifier<AgentRunState> {
  static const String _logName = 'AgentRunViewModel';

  StreamSubscription<AgentEvent>? _events;

  Stopwatch? _clock;
  DateTime? _startedAt;

  @override
  AgentRunState build() {
    ref.onDispose(() => _events?.cancel());
    return const AgentRunState();
  }

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
        toolWarning: await _toolWarningFor(
          _named(library.models, library.activeId),
          agent.template,
        ),
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

  Future<void> selectModel(String id) async {
    state = state.copyWith(modelId: id);
    final template = state.agent?.template;
    if (template == null) return;
    final warning = await _toolWarningFor(
      _named(state.installed, id),
      template,
    );
    // Re-checked: the dropdown can be used again while the catalog is read.
    if (state.modelId != id) return;
    state = state.copyWith(
      toolWarning: warning,
      clearToolWarning: warning == null,
    );
  }

  /// Whether [model] is known not to be able to call tools, worded for the
  /// amber line under the run button.
  ///
  /// Asked of the shipped catalog, which records `tool_calling` per repository
  /// — 19 of its 24 entries carry it. A model that is not in the catalog gets
  /// no warning: it was sideloaded or installed by an older build, and this
  /// cannot tell "cannot" from "unknown".
  ///
  /// Takes the descriptor rather than an id because `open` needs an answer
  /// before it has a state to look one up in.
  Future<String?> _toolWarningFor(
    ModelDescriptor? model,
    AgentTemplate template,
  ) async {
    if (template.toolNames.isEmpty || model == null) return null;

    for (final entry in await ref.read(catalogRepositoryProvider).load()) {
      if (entry.repoId != model.repoId) continue;
      if (entry.capabilities.contains(ModelCapability.toolCalling)) return null;
      return "${entry.name} is not marked as tool-calling — this agent's "
          'tools may never be called.';
    }
    return null;
  }

  static ModelDescriptor? _named(List<ModelDescriptor> models, String? id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

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

  void close() {
    if (_events != null) unawaited(_abandon());
    state = const AgentRunState();
  }

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
  ModelDescriptor? _modelToRun() =>
      _named(state.installed, state.modelId) ??
      (state.installed.isEmpty ? null : state.installed.first);

  Future<String?> _loadWeights(ModelDescriptor model) async {
    try {
      final library = await ref.read(modelLibraryViewModelProvider.future);
      final sampler = await ref.read(samplerViewModelProvider.future);
      return await loadWithFallback(
        llm: ref.read(llmServiceProvider),
        model: model,
        // A step is instruction-following — call this tool, with these
        // arguments — so it samples low whatever the Chat sliders say.
        settings: sampler.forAgentRun(),
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
