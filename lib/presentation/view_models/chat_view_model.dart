import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import '../../domain/services/history_window.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/token_collector.dart';
import 'chat_state.dart';
import 'sessions_view_model.dart';

/// Drives one open conversation. Only one chat screen exists at a time, so
/// this holds the open session directly, which also keeps the single loaded
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

  Future<void> reload() async {
    if (state.session == null) return;
    state = state.copyWith(status: ChatStatus.preparing, clearError: true);
    await _prepare();
  }

  Future<void> send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || !state.canSend) return;

    final prior = state.messages;
    final images = state.attachments;
    final user = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: prompt,
      createdAt: DateTime.now(),
      imagePaths: images,
    );
    await _commit(<ChatMessage>[...prior, user], title: _title(prompt));
    state = state.copyWith(clearAttachments: true);
    await _reseat(prior);
    await _generate(prompt, images);
  }

  /// Puts the model's context back in step with the user's memory budget.
  /// A no-op on most turns — see [needsHistoryReseat] for when it is not.
  Future<void> _reseat(List<ChatMessage> prior) async {
    final turns = await _historyTurns();
    if (!needsHistoryReseat(prior, turns)) return;
    await ref
        .read(llmServiceProvider)
        .restoreHistory(historyWindow(prior, turns));
  }

  Future<int> _historyTurns() async =>
      (await ref.read(samplerViewModelProvider.future)).historyTurns;

  /// Drops the last reply and asks the preceding question again.
  Future<void> regenerate() async {
    if (!state.canRegenerate) return;
    final messages = state.messages;
    final prompt = _lastUserIndex(messages);
    if (prompt < 0) return;

    await _commit(messages.sublist(0, prompt + 1));
    // Rewind the model's context to just before the question, otherwise the
    // discarded reply would still be in scope when it answers again.
    final turns = await _historyTurns();
    await ref
        .read(llmServiceProvider)
        .restoreHistory(historyWindow(messages.sublist(0, prompt), turns));
    // The same question means the same images: asking again without them
    // would be a different question.
    await _generate(messages[prompt].text, messages[prompt].imagePaths);
  }

  void stop() {
    if (!state.isStreaming) return;
    ref.read(llmServiceProvider).stop();
  }

  /// Copies the image the user picked into the app's own storage and holds it
  /// for the next message. The picker hands back a path the platform may
  /// empty, so the copy is what the message ends up pointing at.
  Future<void> attach(String sourcePath) async {
    if (!state.canAttach) return;
    final stored = await ref.read(imageStoreProvider).save(sourcePath);
    if (stored == null) return;
    // Re-checked: the picker is a round trip through another app, and the
    // model may have been switched for a blind one while it was open.
    if (!state.canAttach) {
      await ref.read(imageStoreProvider).delete(<String>[stored]);
      return;
    }
    state = state.copyWith(attachments: <String>[...state.attachments, stored]);
  }

  /// Drops an image from the composer, deleting the copy with it — it was
  /// never on a message, so nothing else can be pointing at it.
  Future<void> removeAttachment(String path) async {
    state = state.copyWith(
      attachments: <String>[
        for (final attachment in state.attachments)
          if (attachment != path) attachment,
      ],
    );
    await ref.read(imageStoreProvider).delete(<String>[path]);
  }

  void close() => state = const ChatState();

  Future<void> _prepare() async {
    final llm = ref.read(llmServiceProvider);
    try {
      // Awaited, not read, so a cold start waits for models.json instead of
      // deciding nothing is installed.
      final library = await ref.read(modelLibraryViewModelProvider.future);
      final model = library.active;
      if (model == null) {
        state = state.copyWith(
          status: ChatStatus.noModel,
          clearError: true,
          clearNotice: true,
        );
        return;
      }

      final settings = await ref.read(samplerViewModelProvider.future);
      final projector = library.projectorFor(model.repoId)?.localPath;
      // Reload when the user switched models in Settings: the loaded weights
      // are still valid, they are simply the wrong ones. A projector that has
      // arrived since counts too — the weights in memory were loaded blind.
      var notice = state.notice;
      if (!llm.isLoaded ||
          llm.loadedModelId != model.id ||
          llm.loadedProjectorPath != projector) {
        notice = await _load(model, settings, projector);
      }
      await llm.restoreHistory(
        historyWindow(state.messages, settings.historyTurns),
      );
      state = state.copyWith(
        status: ChatStatus.ready,
        notice: notice,
        clearNotice: notice == null,
        hasVision: projector != null,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not prepare the model',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        status: ChatStatus.failed,
        error: _describeLoad(error),
        clearNotice: true,
      );
    }
  }

  /// Loads [model], dropping GPU offload rather than giving up on it. Returns
  /// a line to show the user, or null when the load went as asked. The retry
  /// is deliberately not written back to settings: a refused GPU allocation is
  /// about this run, so the next model gets another chance.
  Future<String?> _load(
    ModelDescriptor model,
    SamplerSettings settings,
    String? projectorPath,
  ) async {
    final llm = ref.read(llmServiceProvider);
    final runtime = await ref.read(appSettingsViewModelProvider.future);
    try {
      await llm.load(
        model: model,
        settings: settings,
        runtime: runtime,
        projectorPath: projectorPath,
      );
      return null;
    } catch (error, stackTrace) {
      if (!runtime.useGpu) rethrow;
      developer.log(
        'GPU load failed, retrying on the CPU',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      await llm.load(
        model: model,
        settings: settings,
        runtime: runtime.copyWith(useGpu: false),
        projectorPath: projectorPath,
      );
      return 'Loaded on the CPU — GPU offload was unavailable.';
    }
  }

  Future<void> _generate(
    String prompt, [
    List<String> images = const <String>[],
  ]) async {
    final settings = await ref.read(samplerViewModelProvider.future);
    final collector = TokenCollector(maxTokens: settings.maxTokens);
    final id = _uuid.v4();

    _render(<ChatMessage>[...state.messages, _placeholder(id)]);
    state = state.copyWith(status: ChatStatus.streaming);

    final failure = await _drain(prompt, images, collector, id);
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
    List<String> images,
    TokenCollector collector,
    String id,
  ) async {
    final LlmService llm = ref.read(llmServiceProvider);
    try {
      await for (final token in llm.ask(prompt, imagePaths: images)) {
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
      return _describeGeneration(error);
    }
  }

  ChatMessage _placeholder(String id) => ChatMessage(
    id: id,
    role: MessageRole.assistant,
    text: '',
    createdAt: DateTime.now(),
    isStreaming: true,
  );

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

  /// Kept apart from [_describeGeneration]: a model that never loaded has
  /// generated nothing, and "Generation failed" would misdirect the user.
  static String _describeLoad(Object error) => switch (error) {
    ModelMissingException() => error.toString(),
    ModelLoadException() => error.toString(),
    StateError() => error.message,
    _ => 'Could not load the model: $error',
  };

  static String _describeGeneration(Object error) => switch (error) {
    StateError() => error.message,
    _ => 'Generation failed: $error',
  };
}
