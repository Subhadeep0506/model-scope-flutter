import 'package:json_annotation/json_annotation.dart';

import 'generation_metrics.dart';

part 'chat_message.g.dart';

/// Who produced a message.
enum MessageRole {
  @JsonValue('user')
  user,
  @JsonValue('assistant')
  assistant,
}

/// One turn in a session transcript.
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

  /// Present on finished assistant replies only.
  final GenerationMetrics? metrics;

  /// Images sent with this message, as paths into the app's own storage.
  /// Empty on every assistant reply and on any question asked without one.
  /// A record written before vision support has no `image_paths` key, which
  /// reads as empty — exactly right, so there is nothing to migrate.
  final List<String> imagePaths;

  /// True while tokens are still arriving. Never persisted as true.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool isStreaming;

  /// Set when generation failed, so the transcript can show what went wrong.
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
