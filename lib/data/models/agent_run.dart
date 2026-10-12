import 'package:json_annotation/json_annotation.dart';

part 'agent_run.g.dart';

@JsonEnum()
enum TraceKind {
  @JsonValue('thought')
  thought('thought'),

  @JsonValue('tool')
  tool('tool'),

  @JsonValue('result')
  result('result'),

  @JsonValue('answer')
  answer('answer');

  const TraceKind(this.label);

  final String label;
}

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

  final String label;

  @JsonKey(defaultValue: 0)
  final int durationMs;

  @JsonKey(defaultValue: true)
  final bool ok;

  String get durationLabel => durationMs < 1000
      ? '${durationMs}ms'
      : '${(durationMs / 1000).toStringAsFixed(2)}s';

  Map<String, dynamic> toJson() => _$TraceEntryToJson(this);
}

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
    this.view,
    this.summaryLine,
  });

  factory AgentRun.fromJson(Map<String, dynamic> json) =>
      _$AgentRunFromJson(json);

  final String id;
  final String agentId;

  final String agentName;

  final String modelId;

  final DateTime startedAt;
  final int durationMs;

  @JsonKey(defaultValue: <TraceEntry>[])
  final List<TraceEntry> trace;

  @JsonKey(defaultValue: '')
  final String output;

  final String? error;

  final String? view;

  final String? summaryLine;

  bool get succeeded => error == null;

  String get summary {
    final failure = error;
    if (failure != null) return failure;

    final written = summaryLine?.trim() ?? '';
    final first = written.isNotEmpty
        ? written
        : output
              .split('\n')
              .map((line) => line.trim())
              .firstWhere((line) => line.isNotEmpty, orElse: () => 'No output');
    return first.length <= 72 ? first : '${first.substring(0, 71)}…';
  }

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
