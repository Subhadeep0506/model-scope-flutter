import '../../data/models/chat_message.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/generation_metrics.dart';

/// Where the open conversation is in its lifecycle.
enum ChatStatus {
  idle,
  preparing,
  noModel,
  ready,
  streaming,
  failed,
}

/// Everything the chat screen renders.
class ChatState {
  static const int maxImages = 3;

  const ChatState({
    this.session,
    this.status = ChatStatus.idle,
    this.error,
    this.notice,
    this.attachments = const <String>[],
    this.hasVision = false,
  });

  final ChatSession? session;
  final ChatStatus status;
  final String? error;
  final String? notice;
  final List<String> attachments;
  final bool hasVision;

  List<ChatMessage> get messages => session?.messages ?? const <ChatMessage>[];
  bool get isStreaming => status == ChatStatus.streaming;
  bool get isBusy => isStreaming || status == ChatStatus.preparing;
  bool get canSend => status == ChatStatus.ready;

  bool get canAttach => canSend && hasVision && attachments.length < maxImages;
  bool get canRegenerate =>
      canSend && messages.isNotEmpty && !messages.last.isUser;

  GenerationMetrics? get lastMetrics {
    for (var i = messages.length - 1; i >= 0; i--) {
      final metrics = messages[i].metrics;
      if (metrics != null) return metrics;
    }
    return null;
  }

  ChatState copyWith({
    ChatSession? session,
    ChatStatus? status,
    String? error,
    String? notice,
    List<String>? attachments,
    bool? hasVision,
    bool clearError = false,
    bool clearNotice = false,
    bool clearAttachments = false,
  }) => ChatState(
    session: session ?? this.session,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    notice: clearNotice ? null : (notice ?? this.notice),
    attachments: clearAttachments
        ? const <String>[]
        : (attachments ?? this.attachments),
    hasVision: hasVision ?? this.hasVision,
  );
}
