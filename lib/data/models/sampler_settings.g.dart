// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sampler_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SamplerSettings _$SamplerSettingsFromJson(Map<String, dynamic> json) =>
    SamplerSettings(
      temperature: (json['temperature'] as num?)?.toDouble() ?? _temperature,
      topP: (json['top_p'] as num?)?.toDouble() ?? _topP,
      topK: (json['top_k'] as num?)?.toInt() ?? _topK,
      maxTokens: (json['max_tokens'] as num?)?.toInt() ?? _maxTokens,
      historyTurns: (json['history_turns'] as num?)?.toInt() ?? _historyTurns,
      systemPrompt: json['system_prompt'] as String? ?? _systemPrompt,
    );

Map<String, dynamic> _$SamplerSettingsToJson(SamplerSettings instance) =>
    <String, dynamic>{
      'temperature': instance.temperature,
      'top_p': instance.topP,
      'top_k': instance.topK,
      'max_tokens': instance.maxTokens,
      'history_turns': instance.historyTurns,
      'system_prompt': instance.systemPrompt,
    };
