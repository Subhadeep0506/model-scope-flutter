import '../../data/models/app_settings.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';

/// Thrown by [LlmService.load] when a model's weights are no longer where the
/// registry says they are.
///
/// Carries the path it looked in so the UI can say exactly what happened rather
/// than surfacing an opaque native error. It lives on the interface, not the
/// implementation, so the view models can match on it without importing
/// `package:nobodywho`.
class ModelMissingException implements Exception {
  const ModelMissingException({required this.name, required this.path});

  final String name;
  final String path;

  @override
  String toString() =>
      '$name is no longer on disk. Expected it at $path — remove it in '
      'Settings and download it again.';
}

/// Thrown by [LlmService.load] when the weights are present but the native
/// loader refused them.
///
/// Carries the settings the attempt ran with, because the native message on its
/// own is often just `Failed to load model:` with nothing after it — true and
/// useless. Knowing the context size, whether GPU offload was on, and how the
/// file's length compares to what was downloaded is what separates a corrupt
/// download from a driver that would not allocate from a GGUF this build cannot
/// read. Declared here rather than in the `nobodywho` adapter so the view
/// models can match on it without importing the package.
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

  /// Bytes actually on disk, or null when the length could not be read.
  final int? sizeOnDisk;

  /// Bytes the catalog said the file has.
  final int expectedSize;

  /// The native error, which may be empty.
  final Object cause;

  /// Whether the file is shorter than it should be — the likeliest cause, and
  /// worth saying first.
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

/// The app's view of an on-device language model.
///
/// Everything above this interface is free of `package:nobodywho`, which keeps
/// the view models testable against a fake and makes swapping the inference
/// backend a single-file change.
abstract interface class LlmService {
  /// Whether [load] has completed and [ask] can be called.
  bool get isLoaded;

  /// Id of the model currently in memory, or null when none is.
  ///
  /// Lets the chat view model tell a stale load from a current one now that the
  /// user can switch models from Settings or the Loaded models sheet.
  String? get loadedModelId;

  /// Loads [model] and applies [settings]. Safe to call again for a different
  /// model; the previous one is released.
  ///
  /// [runtime] carries the knobs that can only be set when the model is
  /// created — context size, thread count and GPU offload.
  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
  });

  /// Pushes new sampling settings onto the loaded model without reloading it.
  Future<void> applySettings(SamplerSettings settings);

  /// Replaces the model's context with a restored transcript, so a session
  /// reopened after a restart continues rather than starting cold.
  Future<void> restoreHistory(List<ChatMessage> messages);

  /// Clears the model's context.
  Future<void> resetHistory();

  /// Streams the reply one token per event.
  Stream<String> ask(String prompt);

  /// Asks the model to stop generating. Used to enforce the max-token cap and
  /// to back the stop button.
  void stop();

  /// Releases the model.
  Future<void> dispose();
}
