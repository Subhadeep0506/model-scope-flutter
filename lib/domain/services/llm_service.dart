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
