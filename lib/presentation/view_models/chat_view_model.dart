import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/chat_message.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/token_collector.dart';
import 'chat_state.dart';
import 'sessions_view_model.dart';

/// Drives one open conversation.
///
/// Only one chat screen exists at a time, so this holds the open session
/// directly rather than using a family — which also keeps the single loaded
/// model and this view model in step.
class ChatViewModel extends Notifier<ChatState> {
  static const String _logName = 'ChatViewModel';
  static const Uuid _uuid = Uuid();

  /// How much of the first message becomes the session title.
  static const int _titleLength = 38;

  @override
  ChatState build() => const ChatState();

  /// Loads [sessionId], the weights, and replays the transcript into the
  /// model's context so a reopened session continues rather than starting cold.
  Future<void> open(String sessionId) async {
    await ref.read(sessionsViewModelProvider.future);
    final session = ref
        .read(sessionsViewModelProvider.notifier)
        .byId(sessionId);
    if (session == null) {
      state = const ChatState(
        status: ChatStatus.failed,
        error: 'That conversation no longer exists.',
      );
      return;
    }
    state = ChatState(session: session, status: ChatStatus.preparing);
    await _prepare();
  }

  /// Retries after a failed load, used by the error card.
  Future<void> reload() async {
    if (state.session == null) return;
    state = state.copyWith(status: ChatStatus.preparing, clearError: true);
    await _prepare();
  }

  Future<void> send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || !state.canSend) return;

    final user = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: prompt,
      createdAt: DateTime.now(),
      attachmentName: state.attachmentName,
    );
    await _commit(<ChatMessage>[
      ...state.messages,
      user,
    ], title: _title(prompt));
    state = state.copyWith(clearAttachment: true);
    await _generate(prompt);
  }

  /// Drops the last reply and asks the preceding question again.
  Future<void> regenerate() async {
    if (!state.canRegenerate) return;
    final messages = state.messages;
    final prompt = _lastUserIndex(messages);
    if (prompt < 0) return;

    await _commit(messages.sublist(0, prompt + 1));
    // Rewind the model's context to just before the question, otherwise the
    // discarded reply would still be in scope when it answers again.
    await ref
        .read(llmServiceProvider)
        .restoreHistory(messages.sublist(0, prompt));
    await _generate(messages[prompt].text);
  }

  void stop() {
    if (!state.isStreaming) return;
    ref.read(llmServiceProvider).stop();
  }

  void attach(String? fileName) => state = state.copyWith(
    attachmentName: fileName,
    clearAttachment: fileName == null,
  );

  /// Called when the chat screen is popped.
  void close() => state = const ChatState();

  Future<void> _prepare() async {
    final llm = ref.read(llmServiceProvider);
    try {
      // Reading the library through its future rather than the derived
      // provider, so a cold start waits for models.json instead of deciding
      // nothing is installed.
      final library = await ref.read(modelLibraryViewModelProvider.future);
      final model = library.active;
      if (model == null) {
        state = state.copyWith(status: ChatStatus.noModel, clearError: true);
        return;
      }

      final settings = await ref.read(samplerViewModelProvider.future);
      // Reload when the user switched models in Settings: the loaded weights
      // are still valid, they are simply the wrong ones.
      if (!llm.isLoaded || llm.loadedModelId != model.id) {
        await llm.load(
          model: model,
          settings: settings,
          runtime: await ref.read(appSettingsViewModelProvider.future),
        );
      }
      await llm.restoreHistory(state.messages);
      state = state.copyWith(status: ChatStatus.ready);
    } catch (error, stackTrace) {
      developer.log(
        'Could not prepare the model',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        status: ChatStatus.failed,
        error: _describe(error),
      );
    }
  }

  Future<void> _generate(String prompt) async {
    final settings = await ref.read(samplerViewModelProvider.future);
    final collector = TokenCollector(maxTokens: settings.maxTokens);
    final id = _uuid.v4();

    _render(<ChatMessage>[...state.messages, _placeholder(id)]);
    state = state.copyWith(status: ChatStatus.streaming);

    final failure = await _drain(prompt, collector, id);
    final metrics = collector.finish();

    await _commit(
      _patch(
        id,
        (message) => message.copyWith(
          text: collector.text,
          metrics: metrics,
          isStreaming: false,
          error: failure,
        ),
      ),
    );
    state = state.copyWith(status: ChatStatus.ready);
  }

  /// Consumes the token stream. Returns an error description, or `null`.
  Future<String?> _drain(
    String prompt,
    TokenCollector collector,
    String id,
  ) async {
    final LlmService llm = ref.read(llmServiceProvider);
    try {
      await for (final token in llm.ask(prompt)) {
        final room = collector.add(token);
        _render(_patch(id, (m) => m.copyWith(text: collector.text)));
        if (room) continue;
        // MAX_TOKENS has no sampler equivalent, so the cap is enforced here.
        llm.stop();
        break;
      }
      return null;
    } catch (error, stackTrace) {
      developer.log(
        'Generation failed',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      return _describe(error);
    }
  }

  ChatMessage _placeholder(String id) => ChatMessage(
    id: id,
    role: MessageRole.assistant,
    text: '',
    createdAt: DateTime.now(),
    isStreaming: true,
  );

  /// Returns [state]'s messages with one of them rebuilt.
  List<ChatMessage> _patch(
    String id,
    ChatMessage Function(ChatMessage message) update,
  ) => <ChatMessage>[
    for (final message in state.messages)
      if (message.id == id) update(message) else message,
  ];

  /// Updates the screen without touching disk — used per token.
  void _render(List<ChatMessage> messages) {
    final session = state.session;
    if (session == null) return;
    state = state.copyWith(session: session.copyWith(messages: messages));
  }

  /// Updates the screen and persists, used at each end of turn.
  Future<void> _commit(List<ChatMessage> messages, {String? title}) async {
    final session = state.session;
    if (session == null) return;
    final next = session.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
      title: title,
    );
    state = state.copyWith(session: next);
    await ref.read(sessionsViewModelProvider.notifier).upsert(next);
  }

  /// Names an untitled session after its opening question.
  String? _title(String prompt) {
    if (state.session?.title != SessionsViewModel.untitled) return null;
    final line = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.length <= _titleLength) return line;
    return '${line.substring(0, _titleLength).trimRight()}…';
  }

  static int _lastUserIndex(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) return i;
    }
    return -1;
  }

  static String _describe(Object error) => switch (error) {
    ModelMissingException() => error.toString(),
    StateError() => error.message,
    _ => 'Generation failed: $error',
  };
}
