import 'package:json_annotation/json_annotation.dart';

import 'generation_metrics.dart';

part 'chat_message.g.dart';

enum MessageRole {
  @JsonValue('user')
  user,
  @JsonValue('assistant')
  assistant,
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.metrics,
    this.imagePaths = const <String>[],
    this.isStreaming = false,
    this.error,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  final String id;
  final MessageRole role;
  final String text;
  final DateTime createdAt;

  final GenerationMetrics? metrics;

  final List<String> imagePaths;

  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool isStreaming;

  final String? error;

  bool get isUser => role == MessageRole.user;

  ChatMessage copyWith({
    String? text,
    GenerationMetrics? metrics,
    bool? isStreaming,
    String? error,
  }) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    createdAt: createdAt,
    metrics: metrics ?? this.metrics,
    imagePaths: imagePaths,
    isStreaming: isStreaming ?? this.isStreaming,
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}
