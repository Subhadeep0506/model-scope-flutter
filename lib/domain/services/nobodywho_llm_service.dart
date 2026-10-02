import 'dart:developer' as developer;
import 'dart:io';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../data/models/app_settings.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import 'llm_service.dart';

/// [LlmService] backed by `package:nobodywho`.
///
/// This and the downloader are the only files in the app that import
/// `nobodywho`.
class NobodyWhoLlmService implements LlmService {
  NobodyWhoLlmService();

  static const String _logName = 'NobodyWhoLlmService';

  nobodywho.Chat? _chat;
  String? _loadedModelId;

  @override
  bool get isLoaded => _chat != null;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
  }) async {
    final file = File(model.localPath);
    if (!await file.exists()) {
      throw ModelMissingException(name: model.name, path: model.localPath);
    }

    _chat = null;
    _loadedModelId = null;
    try {
      _chat = await nobodywho.Chat.fromPath(
        modelPath: model.localPath,
        systemPrompt: settings.systemPrompt,
        contextSize: runtime.contextLength,
        threadCount: runtime.cpuThreads,
        useGpu: runtime.useGpu,
        sampler: _samplerFrom(settings),
      );
    } catch (error) {
      throw ModelLoadException(
        name: model.name,
        path: model.localPath,
        contextLength: runtime.contextLength,
        useGpu: runtime.useGpu,
        sizeOnDisk: await _lengthOf(file),
        expectedSize: model.sizeBytes,
        cause: error,
      );
    }
    _loadedModelId = model.id;
    developer.log(
      'Loaded ${model.name} from ${model.localPath} '
      '(context ${runtime.contextLength}, GPU ${runtime.useGpu})',
      name: _logName,
    );
  }

  /// The file's length, or null when it cannot be read — this runs while an
  /// error is already being built, so it must not raise one of its own.
  static Future<int?> _lengthOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> applySettings(SamplerSettings settings) async {
    final chat = _chat;
    if (chat == null) return;
    await chat.setSamplerConfig(_samplerFrom(settings));
    await chat.setSystemPrompt(settings.systemPrompt);
  }

  @override
  Future<void> restoreHistory(List<ChatMessage> messages) async {
    final chat = _chat;
    if (chat == null) return;

    final history = <nobodywho.Message>[];
    for (final message in messages) {
      if (message.text.isEmpty || message.error != null) continue;
      history.add(
        message.isUser
            ? nobodywho.userMessage(message.text)
            : nobodywho.assistantMessage(message.text),
      );
    }

    if (history.isEmpty) {
      await chat.resetHistory();
      return;
    }
    await chat.setChatHistory(history);
  }

  @override
  Future<void> resetHistory() async {
    await _chat?.resetHistory();
  }

  @override
  Stream<String> ask(String prompt) {
    final chat = _chat;
    if (chat == null) {
      return Stream<String>.error(StateError('Model is not loaded yet.'));
    }
    return chat.ask(prompt);
  }

  @override
  void stop() => _chat?.stopGeneration();

  @override
  Future<void> dispose() async {
    _chat = null;
    _loadedModelId = null;
  }

  /// Maps the app's settings onto a `nobodywho` sampler chain.
  ///
  /// `maxTokens` has no equivalent here — the sampler API has no token cap —
  /// so the view model enforces it by counting stream events and calling
  /// [stop].
  nobodywho.SamplerConfig _samplerFrom(SamplerSettings settings) {
    return nobodywho.SamplerBuilder()
        .topK(topK: settings.topK)
        .topP(topP: settings.topP, minKeep: 1)
        .temperature(temperature: settings.temperature)
        .dist();
  }
}
