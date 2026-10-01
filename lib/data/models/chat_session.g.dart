// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatSession _$ChatSessionFromJson(Map<String, dynamic> json) => ChatSession(
  id: json['id'] as String,
  title: json['title'] as String,
  modelId: json['model_id'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  messages:
      (json['messages'] as List<dynamic>?)
          ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ChatMessage>[],
);

Map<String, dynamic> _$ChatSessionToJson(ChatSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'model_id': instance.modelId,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'messages': instance.messages.map((e) => e.toJson()).toList(),
    };
