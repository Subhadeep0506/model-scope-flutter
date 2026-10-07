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
import '../../data/models/sampler_settings.dart';
import '../../data/models/usage_record.dart';
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
            hasModel: library.chatModels.isNotEmpty,
            values: agent.template.defaultValues,
          );

      state = AgentRunState(
        agent: agent,
        status: availability.canRun
            ? AgentRunStatus.idle
            : AgentRunStatus.blocked,
        values: Map<String, String>.of(agent.template.defaultValues),
        modelId: library.activeId,
        installed: library.chatModels,
        error: availability.firstBlocker,
        toolWarning: await _toolWarningFor(
          _named(library.chatModels, library.activeId),
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

  /// Records what the user typed, and rechecks whether the agent can run.
  ///
  /// The recheck matters for an agent with a required input that ships with
  /// no default — Document QnA's file, which cannot have one. Opening it
  /// blocks on `Document needs a value`, and without re-validating here the
  /// run button would stay disabled no matter what the user chose.
  Future<void> setValue(String name, String value) async {
    state = state.copyWith(
      values: <String, String>{...state.values, name: value},
    );

    final template = state.agent?.template;
    // Only while idle or blocked: a run in flight must not have the button
    // re-enabled underneath it.
    if (template == null ||
        (state.status != AgentRunStatus.blocked &&
            state.status != AgentRunStatus.idle)) {
      return;
    }

    final values = state.values;
    final availability = await ref
        .read(agentValidatorProvider)
        .check(template, hasModel: state.installed.isNotEmpty, values: values);
    // The fields can be typed in again while the check is running.
    if (!ref.mounted || state.values != values) return;

    state = state.copyWith(
      status: availability.canRun
          ? AgentRunStatus.idle
          : AgentRunStatus.blocked,
      error: availability.firstBlocker,
      clearError: availability.canRun,
    );
  }

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

  /// Indexes the document if there is one, loads the model, then walks the
  /// pipeline.
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

    // Before the weights, not after: indexing loads the encoder, and holding
    // two models at once on a phone is how an allocation fails.
    if (!await _indexDocument(agent.template)) return;

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

  /// Reads, chunks and encodes the document [template] takes, if it takes one.
  ///
  /// Returns whether the run may continue. A template with no file input is
  /// nothing to do and passes straight through; a failure here ends the run
  /// before any weights are loaded, because an agent that retrieves from an
  /// empty index would answer confidently out of nothing.
  Future<bool> _indexDocument(AgentTemplate template) async {
    final input = template.fileInput;
    if (input == null) return true;

    final path = (state.values[input.name] ?? '').trim();
    if (path.isEmpty) {
      _fail('${input.label} needs a file before this agent can run.');
      return false;
    }

    final library = await ref.read(modelLibraryViewModelProvider.future);
    final embedder = library.embeddingModel;
    if (embedder == null) {
      _fail(
        'No embedding model is installed. Download one under Settings to '
        'search a document.',
      );
      return false;
    }

    state = state.copyWith(status: AgentRunStatus.indexing);
    try {
      await for (final progress
          in ref
              .read(documentIngestorProvider)
              .ingest(path: path, embeddingModel: embedder)) {
        // Left the screen mid-index: nothing left to report to.
        if (!ref.mounted || state.status != AgentRunStatus.indexing) {
          return false;
        }
        _append('index', progress.message);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Could not index the document for ${template.id}',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      _fail('$error');
      return false;
    }

    // Tells the retrieval tool how many passages to fetch and which model
    // encoded them, since the tool was built long before this run existed.
    ref
        .read(retrievalSettingsProvider)
        .apply(
          topK: int.tryParse((state.values['top_k'] ?? '').trim()),
          embeddingModel: embedder,
        );
    // So the Settings card shows what was just indexed.
    ref.read(documentIndexProvider.notifier).refresh();

    state = state.copyWith(status: AgentRunStatus.preparing);
    return true;
  }

  /// [base] with whatever temperature this run should use.
  ///
  /// A run samples low by default, because a step is instruction-following —
  /// call this tool, with these arguments — and sampling loosely there only
  /// makes a small model ignore the tool. Two things may raise it: the
  /// template, for an agent that writes prose from retrieved material, and an
  /// input literally named `temperature`, which lets the user try the same
  /// agent at several settings without editing the file.
  SamplerSettings _samplerFor(SamplerSettings base) {
    final template = state.agent?.template;
    final typed = double.tryParse((state.values['temperature'] ?? '').trim());
    final wanted = typed ?? template?.temperature;
    if (wanted == null) return base;
    return base.copyWith(temperature: wanted.clamp(0, 2));
  }

  /// Ends the run before it started, with [reason] on screen and in the log.
  void _fail(String reason) {
    _append('error', reason, isError: true);
    state = state.copyWith(status: AgentRunStatus.finished, error: reason);
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
    // Read up front: this runs while the screen is being torn down, so by
    // the awaits below the notifier may be gone.
    final usage = _usageOf(run);
    final llm = ref.read(llmServiceProvider);

    llm.stop();
    await _events?.cancel();
    _events = null;
    await ref.read(agentRunRepositoryProvider).add(run);
    // A run the user walked away from still ran, so it still counts.
    if (ref.mounted) {
      await _recordUsage(usage);
      if (ref.mounted) ref.invalidate(agentRunsProvider);
    }
    await llm.dispose();
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
        settings: _samplerFor(sampler.forAgentRun()),
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

    // Built before the awaits below, because each is a chance for the screen
    // to be left and this notifier disposed, after which `state` is gone.
    final usage = _usageOf(run);
    final llm = ref.read(llmServiceProvider);

    await ref.read(agentRunRepositoryProvider).add(run);
    // Every provider touched after an await is guarded: leaving the screen
    // while the run was finishing disposes this notifier, and reaching for a
    // provider through a dead ref throws.
    if (ref.mounted) {
      await _recordUsage(usage);
      if (ref.mounted) ref.invalidate(agentRunsProvider);
    }
    await llm.dispose();
  }

  /// This run as one row of the lifetime ledger.
  ///
  /// The run history file is capped at fifty, so the AGENT RUNS tile cannot
  /// come from it without quietly plateauing. The ledger counts them for
  /// good, and carries no token figures — a run's throughput is spread over
  /// several steps and is not one reply's worth of anything.
  UsageRecord _usageOf(AgentRun run) => UsageRecord(
    at: run.startedAt,
    kind: UsageKind.agentRun,
    modelId: run.modelId,
    modelName: _named(state.installed, run.modelId)?.name ?? '',
    agentId: state.agent?.id ?? run.agentId,
    tokenCount: 0,
    latencyMs: 0,
    tokensPerSecond: 0,
  );

  Future<void> _recordUsage(UsageRecord usage) =>
      ref.read(usageLedgerProvider.notifier).record(usage);

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
