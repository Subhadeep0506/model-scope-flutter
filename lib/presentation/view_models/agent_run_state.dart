import '../../data/models/agent_log.dart';
import '../../data/models/agent_run.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/agent_repository.dart';
import '../../domain/services/thinking_parser.dart';

enum AgentRunStatus {
  loading,
  idle,
  blocked,
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
  final Map<String, String> values;
  final String? modelId;
  final List<ModelDescriptor> installed;
  final bool inputsExpanded;
  final List<TraceEntry> trace;
  final List<AgentLogEntry> logs;
  final String output;
  final String? notice;
  final String? error;
  final String? toolWarning;
  final List<AgentRun> history;
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
  bool get showsStructured => viewing != null
      ? viewing?.view != null
      : agent?.template.answer.isStructured ?? false;

  /// Which component draws it, from the same two sources.
  String? get visibleView {
    final past = viewing;
    if (past != null) {
      final recorded = past.view ?? '';
      return recorded.isEmpty ? null : recorded;
    }
    return agent?.template.answer.view;
  }

  /// The text on screen, from the same two sources as [visibleTrace].
  String get visibleOutput => splitThinking(viewing?.output ?? output).answer;
  bool get isThinking => isRunning && splitThinking(output).isOpen;

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
