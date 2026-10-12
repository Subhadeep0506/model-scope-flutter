import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/generation_metrics.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import '../../data/models/usage_record.dart';
import '../../domain/services/history_window.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/model_loader.dart';
import '../../domain/services/token_collector.dart';
import 'chat_state.dart';
import 'sessions_view_model.dart';

class ChatViewModel extends Notifier<ChatState> {
  static const String _logName = 'ChatViewModel';
  static const Uuid _uuid = Uuid();
  static const int _titleLength = 38;

  @override
  ChatState build() => const ChatState();

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

  Future<void> _reseat(List<ChatMessage> prior) async {
    final turns = await _historyTurns();
    if (!needsHistoryReseat(prior, turns)) return;
    await ref
        .read(llmServiceProvider)
        .restoreHistory(historyWindow(prior, turns));
  }

  Future<int> _historyTurns() async =>
      (await ref.read(samplerViewModelProvider.future)).historyTurns;

  Future<void> regenerate() async {
    if (!state.canRegenerate) return;
    final messages = state.messages;
    final prompt = _lastUserIndex(messages);
    if (prompt < 0) return;

    await _commit(messages.sublist(0, prompt + 1));
    final turns = await _historyTurns();
    await ref
        .read(llmServiceProvider)
        .restoreHistory(historyWindow(messages.sublist(0, prompt), turns));
    await _generate(messages[prompt].text, messages[prompt].imagePaths);
  }

  void stop() {
    if (!state.isStreaming) return;
    ref.read(llmServiceProvider).stop();
  }

  Future<void> attach(String sourcePath) async {
    if (!state.canAttach) return;
    final stored = await ref.read(imageStoreProvider).save(sourcePath);
    if (stored == null) return;
    if (!state.canAttach) {
      await ref.read(imageStoreProvider).delete(<String>[stored]);
      return;
    }
    state = state.copyWith(attachments: <String>[...state.attachments, stored]);
  }

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

  Future<String?> _load(
    ModelDescriptor model,
    SamplerSettings settings,
    String? projectorPath,
  ) async => loadWithFallback(
    llm: ref.read(llmServiceProvider),
    model: model,
    settings: settings,
    runtime: await ref.read(appSettingsViewModelProvider.future),
    projectorPath: projectorPath,
  );

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
    if (failure == null) await _recordUsage(metrics);
    state = state.copyWith(status: ChatStatus.ready);
  }

  /// Writes this reply into the lifetime ledger.
  Future<void> _recordUsage(GenerationMetrics metrics) async {
    if (!ref.mounted) return;

    final model = ref.read(activeModelProvider);
    if (model == null || metrics.tokenCount == 0) return;

    await ref
        .read(usageLedgerProvider.notifier)
        .record(
          UsageRecord(
            at: DateTime.now(),
            modelId: model.id,
            modelName: model.name,
            paramLabel: model.paramLabel,
            quantization: model.quantization,
            tokenCount: metrics.tokenCount,
            latencyMs: metrics.latencyMs,
            tokensPerSecond: metrics.tokensPerSecond,
          ),
        );
  }

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
