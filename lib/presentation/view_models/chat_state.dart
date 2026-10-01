import '../../data/models/chat_message.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/generation_metrics.dart';

/// Where the open conversation is in its lifecycle.
enum ChatStatus {
  /// No session open yet.
  idle,

  /// Loading the weights and restoring the transcript.
  preparing,

  /// Nothing is installed yet. Not a failure — the user has simply not been
  /// to Settings, so the screen offers a way there instead of an error.
  noModel,

  /// Model loaded, waiting for input.
  ready,

  /// Tokens are arriving.
  streaming,

  /// The model could not be loaded; [ChatState.error] says why.
  failed,
}

/// Everything the chat screen renders.
class ChatState {
  const ChatState({
    this.session,
    this.status = ChatStatus.idle,
    this.error,
    this.attachmentName,
  });

  final ChatSession? session;
  final ChatStatus status;

  /// Set only for model-level failures, which replace the composer with an
  /// actionable card. Per-reply failures live on the message instead.
  final String? error;

  /// A picked file waiting in the composer. Recorded on the next message for
  /// display only — the model is text-only and never receives it.
  final String? attachmentName;

  List<ChatMessage> get messages => session?.messages ?? const <ChatMessage>[];

  bool get isStreaming => status == ChatStatus.streaming;

  bool get isBusy => isStreaming || status == ChatStatus.preparing;

  /// The composer only accepts input once the weights are in memory.
  bool get canSend => status == ChatStatus.ready;

  /// Regenerate needs a finished reply to replace.
  bool get canRegenerate =>
      canSend && messages.isNotEmpty && !messages.last.isUser;

  /// Throughput of the most recent reply, shown in the Loaded models sheet.
  /// `null` until this session has produced one.
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
    String? attachmentName,
    bool clearError = false,
    bool clearAttachment = false,
  }) => ChatState(
    session: session ?? this.session,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    attachmentName: clearAttachment
        ? null
        : (attachmentName ?? this.attachmentName),
  );
}
