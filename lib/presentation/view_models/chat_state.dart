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
  /// How many images one message may carry. Each one costs hundreds of tokens
  /// of a context the user budgets in turns, so the composer caps it rather
  /// than letting a question arrive with no room left to answer it.
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

  /// Set only for model-level failures, which replace the composer with an
  /// actionable card. Per-reply failures live on the message instead.
  final String? error;

  /// A line about how the model loaded, when it did not load as asked —
  /// currently only the CPU fallback. The chat stays usable, unlike [error].
  final String? notice;

  /// Images waiting in the composer, as paths into the app's own storage.
  /// They go out with the next message and the composer then clears.
  final List<String> attachments;

  /// Whether the loaded model has a projector and can therefore read images.
  final bool hasVision;

  List<ChatMessage> get messages => session?.messages ?? const <ChatMessage>[];

  bool get isStreaming => status == ChatStatus.streaming;

  bool get isBusy => isStreaming || status == ChatStatus.preparing;

  /// The composer only accepts input once the weights are in memory.
  bool get canSend => status == ChatStatus.ready;

  /// Whether another image can be picked. A model without a projector cannot
  /// read one, so the composer offers nothing rather than taking a picture it
  /// would have to throw away.
  bool get canAttach => canSend && hasVision && attachments.length < maxImages;

  /// Regenerate needs a finished reply to replace.
  bool get canRegenerate =>
      canSend && messages.isNotEmpty && !messages.last.isUser;

  /// Throughput of the most recent reply, shown in the Loaded models sheet.
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
