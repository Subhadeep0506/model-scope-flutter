import 'package:json_annotation/json_annotation.dart';

part 'agent_run.g.dart';

/// What kind of line a trace row is. These are the four labels the run screen
/// prints down the left of the trace, in the colour each is drawn in.
@JsonEnum()
enum TraceKind {
  /// A reason step: the model thinking, with no tool in reach.
  @JsonValue('thought')
  thought('thought'),

  /// The model asking for a tool, with the arguments it chose.
  @JsonValue('tool')
  tool('tool'),

  /// What that tool gave back.
  @JsonValue('result')
  result('result'),

  /// The closing step.
  @JsonValue('answer')
  answer('answer');

  const TraceKind(this.label);

  /// Printed in mono at the head of the row, e.g. `tool`.
  final String label;
}

/// One row of the trace.
@JsonSerializable(fieldRename: FieldRename.snake)
class TraceEntry {
  const TraceEntry({
    required this.kind,
    required this.label,
    this.durationMs = 0,
    this.ok = true,
  });

  factory TraceEntry.fromJson(Map<String, dynamic> json) =>
      _$TraceEntryFromJson(json);

  final TraceKind kind;

  /// What follows the kind, e.g. `web_search("sony wh-1000xm5")` or
  /// `Final briefing`.
  final String label;

  /// How long this row took. On a tool row it is the whole step's time, not
  /// the tool call's alone — see [AgentRun] for why.
  @JsonKey(defaultValue: 0)
  final int durationMs;

  /// Whether the step succeeded. A failed row is the last one in the trace.
  @JsonKey(defaultValue: true)
  final bool ok;

  /// `312ms`, or `4.20s` once a row runs past a second.
  String get durationLabel => durationMs < 1000
      ? '${durationMs}ms'
      : '${(durationMs / 1000).toStringAsFixed(2)}s';

  Map<String, dynamic> toJson() => _$TraceEntryToJson(this);
}

/// One finished run of one agent, as listed under `RUN HISTORY`.
///
/// A note on timings: a tool row carries the duration of the step that made
/// the call, not of the call itself. `nobodywho` runs its tool loop inside
/// Rust and reports the calls only afterwards, through the chat history, with
/// no clock attached. Timing each call would mean wrapping the tool's Dart
/// function, which changes its `runtimeType` — and that is exactly what the
/// library reads to build the tool's schema.
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AgentRun {
  const AgentRun({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.modelId,
    required this.startedAt,
    required this.durationMs,
    this.trace = const <TraceEntry>[],
    this.output = '',
    this.error,
  });

  factory AgentRun.fromJson(Map<String, dynamic> json) =>
      _$AgentRunFromJson(json);

  final String id;
  final String agentId;

  /// Stored rather than looked up, so history survives the agent being
  /// renamed or deleted.
  final String agentName;

  /// Id of the [ModelDescriptor] that ran it.
  final String modelId;

  final DateTime startedAt;
  final int durationMs;

  @JsonKey(defaultValue: <TraceEntry>[])
  final List<TraceEntry> trace;

  /// The final text. Present even on a failed run when the failure came after
  /// some of the answer had streamed.
  @JsonKey(defaultValue: '')
  final String output;

  /// Why the run stopped early, or null when it finished.
  final String? error;

  bool get succeeded => error == null;

  /// The first line of the output, which is what the history card shows as its
  /// title. Falls back to the error, so a failed run is not a blank row.
  String get summary {
    final failure = error;
    if (failure != null) return failure;

    final first = output
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => 'No output');
    return first.length <= 72 ? first : '${first.substring(0, 71)}…';
  }

  /// `qwen25-15b · 8 steps · 4.24s`, the mono line under the summary.
  String get statsLabel {
    final steps = trace.length;
    final seconds = (durationMs / 1000).toStringAsFixed(2);
    return '$modelId · $steps ${steps == 1 ? 'step' : 'steps'} · ${seconds}s';
  }

  Map<String, dynamic> toJson() => _$AgentRunToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AgentRun && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
