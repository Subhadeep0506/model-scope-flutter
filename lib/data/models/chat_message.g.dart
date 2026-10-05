// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  id: json['id'] as String,
  role: $enumDecode(_$MessageRoleEnumMap, json['role']),
  text: json['text'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  metrics: json['metrics'] == null
      ? null
      : GenerationMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
  imagePaths:
      (json['image_paths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  error: json['error'] as String?,
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': _$MessageRoleEnumMap[instance.role]!,
      'text': instance.text,
      'created_at': instance.createdAt.toIso8601String(),
      'metrics': instance.metrics?.toJson(),
      'image_paths': instance.imagePaths,
      'error': instance.error,
    };

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
};
