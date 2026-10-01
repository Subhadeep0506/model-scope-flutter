// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'generation_metrics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GenerationMetrics _$GenerationMetricsFromJson(Map<String, dynamic> json) =>
    GenerationMetrics(
      latencyMs: (json['latency_ms'] as num).toInt(),
      tokensPerSecond: (json['tokens_per_second'] as num).toDouble(),
      tokenCount: (json['token_count'] as num).toInt(),
    );

Map<String, dynamic> _$GenerationMetricsToJson(GenerationMetrics instance) =>
    <String, dynamic>{
      'latency_ms': instance.latencyMs,
      'tokens_per_second': instance.tokensPerSecond,
      'token_count': instance.tokenCount,
    };
