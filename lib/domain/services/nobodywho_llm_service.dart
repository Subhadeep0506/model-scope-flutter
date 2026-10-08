import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../data/models/app_settings.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import '../tools/nobodywho_tools.dart';
import '../tools/tool_definition.dart';
import 'history_window.dart';
import 'llm_service.dart';

/// [LlmService] backed by `package:nobodywho`.
class NobodyWhoLlmService implements LlmService {
  NobodyWhoLlmService();

  static const String _logName = 'NobodyWhoLlmService';

  nobodywho.Chat? _chat;
  String? _loadedModelId;
  String? _loadedProjectorPath;

  /// The settings the sampler is built from, kept so a response schema can be
  /// lifted again. A constrained sampler replaces the chain wholesale rather
  /// than adding a step to it, so there is nothing to restore from unless the
  /// settings that built it were held on to.
  SamplerSettings? _settings;

  @override
  bool get isLoaded => _chat != null;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  String? get loadedProjectorPath => _loadedProjectorPath;

  @override
  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
    String? projectorPath,
  }) async {
    final file = File(model.localPath);
    if (!await file.exists()) {
      throw ModelMissingException(name: model.name, path: model.localPath);
    }

    final projector = await _usableProjector(projectorPath);

    _chat = null;
    _loadedModelId = null;
    _loadedProjectorPath = null;
    _settings = settings;
    try {
      _chat = await nobodywho.Chat.fromPath(
        modelPath: model.localPath,
        projectionModelPath: projector,
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
    _loadedProjectorPath = projector;
    developer.log(
      'Loaded ${model.name} from ${model.localPath} '
      '(context ${runtime.contextLength}, GPU ${runtime.useGpu}, '
      'vision ${projector == null ? 'off' : 'on'})',
      name: _logName,
    );
  }

  static Future<String?> _usableProjector(String? path) async {
    if (path == null) return null;
    if (await File(path).exists()) return path;
    developer.log('Projector $path is gone, loading text-only', name: _logName);
    return null;
  }

  static Future<int?> _lengthOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> applySettings(SamplerSettings settings) async {
    _settings = settings;
    final chat = _chat;
    if (chat == null) return;
    await chat.setSamplerConfig(_samplerFrom(settings));
    await chat.setSystemPrompt(settings.systemPrompt);
  }

  @override
  Future<void> setResponseSchema(Map<String, dynamic>? schema) async {
    final chat = _chat;
    if (chat == null) return;

    if (schema == null) {
      // Back to the chain the settings describe. The constrained sampler is a
      // whole config rather than a step, so lifting it means rebuilding.
      final settings = _settings;
      if (settings != null) await chat.setSamplerConfig(_samplerFrom(settings));
      return;
    }

    // Throws when llguidance will not compile the schema, which the caller
    // handles — an agent falls back to an unconstrained answer rather than
    // losing the run.
    await chat.setSamplerConfig(
      nobodywho.SamplerPresets.constrainWithJsonSchema(schema: schema),
    );
    developer.log(
      'Constrained the next reply to a ${schema.length}-key schema',
      name: _logName,
    );
  }

  @override
  Future<void> setSystemPrompt(String prompt) async {
    await _chat?.setSystemPrompt(prompt);
  }

  @override
  Future<void> setThinking(bool enabled) async {
    await _chat?.setTemplateVariable('enable_thinking', enabled);
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
            ? nobodywho.userMessage(withImageMarkers(message))
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
  Future<void> setTools(List<ToolDefinition> tools) async {
    await _chat?.setTools(toNobodyWhoTools(tools));
  }

  @override
  Future<List<ToolInvocation>> recentToolCalls() async {
    final chat = _chat;
    if (chat == null) return const <ToolInvocation>[];
    return _pairCalls(await chat.getChatHistory());
  }

  static List<ToolInvocation> _pairCalls(List<nobodywho.Message> history) {
    final calls = <nobodywho.ToolCall>[];
    final results = <String>[];

    for (final message in history) {
      switch (message) {
        case nobodywho.Message_Assistant(:final toolCalls?):
          calls.addAll(toolCalls);
        case nobodywho.Message_Tool(:final content):
          results.add(content.text);
        default:
          break;
      }
    }

    return <ToolInvocation>[
      for (final (index, call) in calls.indexed)
        ToolInvocation(
          name: call.name,
          arguments: _describeArguments(call.arguments),
          rawArguments: call.arguments?.toString() ?? '',
          result: index < results.length ? results[index] : '',
        ),
    ];
  }

  static String _describeArguments(Object? arguments) {
    final decoded = switch (arguments) {
      final String text when text.trim().startsWith('{') => _tryDecode(text),
      final String text => text,
      _ => arguments,
    };

    if (decoded is Map && decoded.isNotEmpty) {
      return decoded.values.map((value) => jsonEncode(value)).join(', ');
    }
    return decoded == null ? '' : decoded.toString();
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  Stream<String> ask(
    String prompt, {
    List<String> imagePaths = const <String>[],
  }) {
    final chat = _chat;
    if (chat == null) {
      return Stream<String>.error(StateError('Model is not loaded yet.'));
    }
    if (imagePaths.isEmpty) return chat.ask(prompt);

    // Images first: vision models are trained on the picture arriving before
    // the question about it, and the order measurably changes the answer.
    return chat.askWithPrompt(
      nobodywho.Prompt(<nobodywho.PromptPart>[
        for (final path in imagePaths) nobodywho.ImagePart(path),
        nobodywho.TextPart(prompt),
      ]),
    );
  }

  @override
  void stop() => _chat?.stopGeneration();

  @override
  Future<void> dispose() async {
    _chat = null;
    _loadedModelId = null;
    _loadedProjectorPath = null;
    _settings = null;
  }

  /// Maps the app's settings onto a `nobodywho` sampler chain. `maxTokens` has
  /// no equivalent — the view model enforces it by counting and calling [stop].
  nobodywho.SamplerConfig _samplerFrom(SamplerSettings settings) {
    return nobodywho.SamplerBuilder()
        .topK(topK: settings.topK)
        .topP(topP: settings.topP, minKeep: 1)
        .temperature(temperature: settings.temperature)
        .dist();
  }
}
