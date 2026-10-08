import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/agent_repository.dart';
import '../../domain/services/thinking_parser.dart';

enum AgentRunStatus {
  loading,
  idle,
  blocked,

  /// Reading and encoding the picked document, before any weights are loaded.
  /// Its own status because it can take tens of seconds on a long PDF, and
  /// `Loading the model` would be a lie about what the wait is for.
  indexing,

  preparing,
  running,
  finished,
  failed,
}

/// Everything the agent detail screen draws.
class AgentRunState {
  const AgentRunState({
    this.agent,
    this.status = AgentRunStatus.loading,
    this.values = const <String, String>{},
    this.modelId,
    this.installed = const <ModelDescriptor>[],
    this.inputsExpanded = false,
    this.trace = const <TraceEntry>[],
    this.logs = const <AgentLogEntry>[],
    this.output = '',
    this.notice,
    this.error,
    this.toolWarning,
    this.history = const <AgentRun>[],
    this.viewing,
  });

  final Agent? agent;
  final AgentRunStatus status;

  /// What the user has filled in, by input name. Seeded from the template's
  /// defaults when the screen opens.
  final Map<String, String> values;

  /// The model this run will use. Defaults to the one active in Settings and
  /// is deliberately kept here rather than written back — picking a model to
  /// run an agent on should not change what Chat answers with.
  final String? modelId;

  /// Installed models, for the MODEL dropdown.
  final List<ModelDescriptor> installed;

  final bool inputsExpanded;

  /// The rows gathered so far. Grows while [status] is
  /// [AgentRunStatus.running].
  final List<TraceEntry> trace;

  /// The verbose log behind [trace], shown by `Show logs`. Live only — see
  /// [AgentLogEntry].
  final List<AgentLogEntry> logs;

  /// The final text, growing token by token as it is written.
  final String output;

  /// `Loaded on the CPU — GPU offload was unavailable.`, or null.
  final String? notice;

  /// Why the run stopped, or why the agent could not be opened.
  final String? error;

  /// That the chosen model is not marked as able to call tools. A warning
  /// rather than a blocker: watching a model fail to reach for a tool is a
  /// legitimate thing to want to see here.
  final String? toolWarning;

  /// This agent's past runs, newest first.
  final List<AgentRun> history;

  /// A past run the user opened from `RUN HISTORY`, drawn read-only. Null when
  /// the screen is showing the live run.
  final AgentRun? viewing;

  /// Whether the screen is showing a run rather than the configuration.
  bool get showsRun =>
      viewing != null ||
      status == AgentRunStatus.indexing ||
      status == AgentRunStatus.preparing ||
      status == AgentRunStatus.running ||
      status == AgentRunStatus.finished;

  bool get isRunning =>
      status == AgentRunStatus.indexing ||
      status == AgentRunStatus.preparing ||
      status == AgentRunStatus.running;

  bool get canRun =>
      agent != null && !isRunning && status != AgentRunStatus.loading;

  /// Whether nothing has been edited, which is what flips the run button
  /// between `Run with defaults` and `Run configured`.
  bool get usesDefaults {
    final defaults = agent?.template.defaultValues ?? const <String, String>{};
    if (defaults.length != values.length) return false;
    for (final entry in values.entries) {
      if (defaults[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// The rows on screen: the live run's, or the one being looked back at.
  List<TraceEntry> get visibleTrace => viewing?.trace ?? trace;

  /// Whether the output on screen should be drawn as a component rather than
  /// as prose.
  ///
  /// A past run answers from what it recorded, not from the template: an
  /// agent given a schema today must not make last week's prose runs try to
  /// render as a table, and one whose schema was removed must not stop its
  /// old structured runs drawing.
  bool get showsStructured => viewing != null
      ? viewing?.view != null
      : agent?.template.answer.isStructured ?? false;

  /// Which component draws it, from the same two sources.
  String? get visibleView {
    final past = viewing;
    if (past != null) {
      // Recorded as empty for a structured run whose agent named no view,
      // which falls back to the generic table — same as a null here would.
      final recorded = past.view ?? '';
      return recorded.isEmpty ? null : recorded;
    }
    return agent?.template.answer.view;
  }

  /// The text on screen, from the same two sources as [visibleTrace].
  ///
  /// Stripped of any reasoning block. The tokens arrive raw so the screen can
  /// fill in as they stream — the same arrangement Chat uses — but an agent
  /// shows the answer alone. The reasoning is in the run log for anyone who
  /// wants it.
  String get visibleOutput => splitThinking(viewing?.output ?? output).answer;

  /// Whether the model is still inside a reasoning block, which is what puts
  /// `Thinking…` on the output card instead of `Writing…`.
  bool get isThinking => isRunning && splitThinking(output).isOpen;

  /// `4.20s total`, printed opposite the TRACE heading.
  String get traceTotalLabel {
    final total =
        viewing?.durationMs ??
        visibleTrace.fold<int>(0, (sum, entry) => sum + entry.durationMs);
    return '${(total / 1000).toStringAsFixed(2)}s total';
  }

  AgentRunState copyWith({
    Agent? agent,
    AgentRunStatus? status,
    Map<String, String>? values,
    String? modelId,
    List<ModelDescriptor>? installed,
    bool? inputsExpanded,
    List<TraceEntry>? trace,
    List<AgentLogEntry>? logs,
    String? output,
    String? notice,
    String? error,
    String? toolWarning,
    List<AgentRun>? history,
    AgentRun? viewing,
    bool clearNotice = false,
    bool clearError = false,
    bool clearViewing = false,
    bool clearToolWarning = false,
  }) => AgentRunState(
    agent: agent ?? this.agent,
    status: status ?? this.status,
    values: values ?? this.values,
    modelId: modelId ?? this.modelId,
    installed: installed ?? this.installed,
    inputsExpanded: inputsExpanded ?? this.inputsExpanded,
    trace: trace ?? this.trace,
    logs: logs ?? this.logs,
    output: output ?? this.output,
    notice: clearNotice ? null : notice ?? this.notice,
    error: clearError ? null : error ?? this.error,
    toolWarning: clearToolWarning ? null : toolWarning ?? this.toolWarning,
    history: history ?? this.history,
    viewing: clearViewing ? null : viewing ?? this.viewing,
  );
}
