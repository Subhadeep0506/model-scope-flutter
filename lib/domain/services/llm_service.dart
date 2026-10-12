import '../../data/models/app_settings.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import '../tools/tool_definition.dart';

class ToolInvocation {
  const ToolInvocation({
    required this.name,
    required this.arguments,
    required this.result,
    this.rawArguments = '',
  });
  final String name;
  final String arguments;
  final String rawArguments;
  final String result;
  String get signature => '$name($arguments)';
}

class ModelMissingException implements Exception {
  const ModelMissingException({required this.name, required this.path});

  final String name;
  final String path;

  @override
  String toString() =>
      '$name is no longer on disk. Expected it at $path — remove it in '
      'Settings and download it again.';
}

class ModelLoadException implements Exception {
  const ModelLoadException({
    required this.name,
    required this.path,
    required this.contextLength,
    required this.useGpu,
    required this.sizeOnDisk,
    required this.expectedSize,
    required this.cause,
  });

  final String name;
  final String path;
  final int contextLength;
  final bool useGpu;
  final int? sizeOnDisk;
  final int expectedSize;
  final Object cause;

  bool get isTruncated {
    final size = sizeOnDisk;
    return size != null && size < expectedSize;
  }

  @override
  String toString() {
    final detail = cause.toString().trim();
    final reason = detail.isEmpty ? 'no reason given' : detail;
    if (isTruncated) {
      return 'Could not load $name: the file is incomplete, $sizeOnDisk of '
          '$expectedSize bytes. Remove it in Settings and download it again.';
    }
    return 'Could not load $name ($reason). Context $contextLength, GPU '
        '${useGpu ? 'on' : 'off'}, $sizeOnDisk bytes at $path.';
  }
}

abstract interface class LlmService {
  bool get isLoaded;
  String? get loadedModelId;
  String? get loadedProjectorPath;

  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
    String? projectorPath,
  });

  Future<void> applySettings(SamplerSettings settings);
  Future<void> setResponseSchema(Map<String, dynamic>? schema);
  Future<void> setThinking(bool enabled);
  Future<void> setSystemPrompt(String prompt);
  Future<void> restoreHistory(List<ChatMessage> messages);
  Future<void> resetHistory();
  Future<void> setTools(List<ToolDefinition> tools);
  Future<List<ToolInvocation>> recentToolCalls();
  Stream<String> ask(String prompt, {List<String> imagePaths});
  void stop();
  Future<void> dispose();
}
