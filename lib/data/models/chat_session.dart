import 'package:json_annotation/json_annotation.dart';

import 'chat_message.dart';

part 'chat_session.g.dart';

/// A named conversation, as listed on the Chats screen.
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.modelId,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const <ChatMessage>[],
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);

  final String id;
  final String title;

  /// Id of the [ModelDescriptor] this session talks to.
  final String modelId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  int get messageCount => messages.length;

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) => ChatSession(
    id: id,
    title: title ?? this.title,
    modelId: modelId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );

  Map<String, dynamic> toJson() => _$ChatSessionToJson(this);
}
