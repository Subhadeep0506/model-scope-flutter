import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/agent_repository.dart';

/// Where the agent detail screen is in a run.
enum AgentRunStatus {
  /// Reading the agent and its history. The screen shows a spinner.
  loading,

  /// Ready to run: description, model, inputs and the run button.
  idle,

  /// Something stops it running — no model, no key, a broken template. Same
  /// screen as [idle] with the run button disabled and the reason under it.
  blocked,

  /// Loading the weights. This is the only point at which a model is loaded;
  /// opening the screen loads nothing.
  preparing,

  /// Walking the pipeline. The trace fills in and the answer streams.
  running,

  /// The run ended. Trace and output stay on screen until the user leaves or
  /// runs again.
  finished,

  /// The agent could not be opened at all.
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

  /// This agent's past runs, newest first.
  final List<AgentRun> history;

  /// A past run the user opened from `RUN HISTORY`, drawn read-only. Null when
  /// the screen is showing the live run.
  final AgentRun? viewing;

  /// Whether the screen is showing a run rather than the configuration.
  bool get showsRun =>
      viewing != null ||
      status == AgentRunStatus.preparing ||
      status == AgentRunStatus.running ||
      status == AgentRunStatus.finished;

  bool get isRunning =>
      status == AgentRunStatus.preparing || status == AgentRunStatus.running;

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

  /// The text on screen, from the same two sources as [visibleTrace].
  String get visibleOutput => viewing?.output ?? output;

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
    List<AgentRun>? history,
    AgentRun? viewing,
    bool clearNotice = false,
    bool clearError = false,
    bool clearViewing = false,
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
    history: history ?? this.history,
    viewing: clearViewing ? null : viewing ?? this.viewing,
  );
}
