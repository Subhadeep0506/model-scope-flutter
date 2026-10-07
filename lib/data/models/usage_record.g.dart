// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usage_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UsageRecord _$UsageRecordFromJson(Map<String, dynamic> json) => UsageRecord(
  at: DateTime.parse(json['at'] as String),
  modelId: json['model_id'] as String,
  tokenCount: (json['token_count'] as num).toInt(),
  latencyMs: (json['latency_ms'] as num).toInt(),
  tokensPerSecond: (json['tokens_per_second'] as num).toDouble(),
  kind: $enumDecodeNullable(_$UsageKindEnumMap, json['kind']) ?? UsageKind.chat,
  modelName: json['model_name'] as String? ?? '',
  paramLabel: json['param_label'] as String?,
  quantization: json['quantization'] as String? ?? '',
  agentId: json['agent_id'] as String?,
);

Map<String, dynamic> _$UsageRecordToJson(UsageRecord instance) =>
    <String, dynamic>{
      'at': instance.at.toIso8601String(),
      'model_id': instance.modelId,
      'token_count': instance.tokenCount,
      'latency_ms': instance.latencyMs,
      'tokens_per_second': instance.tokensPerSecond,
      'kind': _$UsageKindEnumMap[instance.kind]!,
      'model_name': instance.modelName,
      'param_label': instance.paramLabel,
      'quantization': instance.quantization,
      'agent_id': instance.agentId,
    };

const _$UsageKindEnumMap = {
  UsageKind.chat: 'chat',
  UsageKind.agentRun: 'agent_run',
};

UsageTotals _$UsageTotalsFromJson(Map<String, dynamic> json) => UsageTotals(
  replies: (json['replies'] as num?)?.toInt() ?? 0,
  tokens: (json['tokens'] as num?)?.toInt() ?? 0,
  latencySumMs: (json['latency_sum_ms'] as num?)?.toInt() ?? 0,
  peakTokensPerSecond:
      (json['peak_tokens_per_second'] as num?)?.toDouble() ?? 0,
  peakModelId: json['peak_model_id'] as String?,
  peakModelName: json['peak_model_name'] as String?,
  agentRuns: (json['agent_runs'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$UsageTotalsToJson(UsageTotals instance) =>
    <String, dynamic>{
      'replies': instance.replies,
      'tokens': instance.tokens,
      'latency_sum_ms': instance.latencySumMs,
      'peak_tokens_per_second': instance.peakTokensPerSecond,
      'peak_model_id': instance.peakModelId,
      'peak_model_name': instance.peakModelName,
      'agent_runs': instance.agentRuns,
    };

ModelTotals _$ModelTotalsFromJson(Map<String, dynamic> json) => ModelTotals(
  modelId: json['model_id'] as String,
  name: json['name'] as String? ?? '',
  quantization: json['quantization'] as String? ?? '',
  paramLabel: json['param_label'] as String?,
  replies: (json['replies'] as num?)?.toInt() ?? 0,
  tokens: (json['tokens'] as num?)?.toInt() ?? 0,
  latencySumMs: (json['latency_sum_ms'] as num?)?.toInt() ?? 0,
  tokensPerSecondSum: (json['tokens_per_second_sum'] as num?)?.toDouble() ?? 0,
  lastUsedAt: json['last_used_at'] == null
      ? null
      : DateTime.parse(json['last_used_at'] as String),
);

Map<String, dynamic> _$ModelTotalsToJson(ModelTotals instance) =>
    <String, dynamic>{
      'model_id': instance.modelId,
      'name': instance.name,
      'quantization': instance.quantization,
      'param_label': instance.paramLabel,
      'replies': instance.replies,
      'tokens': instance.tokens,
      'latency_sum_ms': instance.latencySumMs,
      'tokens_per_second_sum': instance.tokensPerSecondSum,
      'last_used_at': instance.lastUsedAt?.toIso8601String(),
    };
