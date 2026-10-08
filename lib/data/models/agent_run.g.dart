// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TraceEntry _$TraceEntryFromJson(Map<String, dynamic> json) => TraceEntry(
  kind: $enumDecode(_$TraceKindEnumMap, json['kind']),
  label: json['label'] as String,
  durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
  ok: json['ok'] as bool? ?? true,
);

Map<String, dynamic> _$TraceEntryToJson(TraceEntry instance) =>
    <String, dynamic>{
      'kind': _$TraceKindEnumMap[instance.kind]!,
      'label': instance.label,
      'duration_ms': instance.durationMs,
      'ok': instance.ok,
    };

const _$TraceKindEnumMap = {
  TraceKind.thought: 'thought',
  TraceKind.tool: 'tool',
  TraceKind.result: 'result',
  TraceKind.answer: 'answer',
};

AgentRun _$AgentRunFromJson(Map<String, dynamic> json) => AgentRun(
  id: json['id'] as String,
  agentId: json['agent_id'] as String,
  agentName: json['agent_name'] as String,
  modelId: json['model_id'] as String,
  startedAt: DateTime.parse(json['started_at'] as String),
  durationMs: (json['duration_ms'] as num).toInt(),
  trace:
      (json['trace'] as List<dynamic>?)
          ?.map((e) => TraceEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  output: json['output'] as String? ?? '',
  error: json['error'] as String?,
  view: json['view'] as String?,
  summaryLine: json['summary_line'] as String?,
);

Map<String, dynamic> _$AgentRunToJson(AgentRun instance) => <String, dynamic>{
  'id': instance.id,
  'agent_id': instance.agentId,
  'agent_name': instance.agentName,
  'model_id': instance.modelId,
  'started_at': instance.startedAt.toIso8601String(),
  'duration_ms': instance.durationMs,
  'trace': instance.trace.map((e) => e.toJson()).toList(),
  'output': instance.output,
  'error': instance.error,
  'view': instance.view,
  'summary_line': instance.summaryLine,
};
