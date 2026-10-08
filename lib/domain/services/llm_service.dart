import '../../data/models/app_settings.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/sampler_settings.dart';
import '../tools/tool_definition.dart';

/// One tool call the model made, and what came back.
///
/// Reconstructed after the fact rather than observed as it happens:
/// `nobodywho` runs its tool loop inside Rust and the token stream carries
/// only the final answer, so a call is visible only once it is in the chat
/// history. That is enough to draw the trace, but it means there is no clock
/// on an individual call — see `AgentRun` for what the trace reports instead.
class ToolInvocation {
  const ToolInvocation({
    required this.name,
    required this.arguments,
    required this.result,
    this.rawArguments = '',
  });

  final String name;

  /// What the model passed, flattened to one line for the trace — the trace
  /// row reads `web_search("sony wh-1000xm5")`.
  final String arguments;

  /// The same arguments as the backend gave them, with their names intact:
  /// `{"query": "sony wh-1000xm5"}`. [arguments] drops the names to fit a
  /// trace row; the run log keeps them, because a model passing the right
  /// value under the wrong name is a failure worth being able to see.
  final String rawArguments;

  /// What the tool returned, which is what went back into the context.
  final String result;

  /// `web_search("sony wh-1000xm5")`, or `web_search()` when it passed
  /// nothing.
  String get signature => '$name($arguments)';
}

/// Thrown by [LlmService.load] when a model's weights are no longer where the
/// registry says they are. Declared here, not in the `nobodywho` adapter, so
/// the view models can match on it without importing the package.
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
/// loader refused them. Carries the settings the attempt ran with, because the
/// native message on its own is often just `Failed to load model:` — the
/// context size, GPU flag and file length are what separate a corrupt download
/// from a driver that would not allocate.
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

  /// The likeliest cause, and worth saying first.
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

/// The app's view of an on-device language model. Everything above this
/// interface is free of `package:nobodywho`, which keeps the view models
/// testable and makes swapping the backend a single-file change.
abstract interface class LlmService {
  /// Whether [load] has completed and [ask] can be called.
  bool get isLoaded;

  /// Id of the model in memory, or null when none is. Lets the chat view model
  /// tell a stale load from a current one.
  String? get loadedModelId;

  /// Path of the vision projector in memory, or null when the model was loaded
  /// without one. A projector downloaded after the weights were loaded changes
  /// this, which is how the chat knows to reload rather than stay blind.
  String? get loadedProjectorPath;

  /// Loads [model] and applies [settings], releasing any previous model.
  /// [runtime] carries the knobs that can only be set at creation — context
  /// size, thread count and GPU offload. [projectorPath] is the `mmproj` file
  /// that lets the model read images; without one it loads text-only.
  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
    String? projectorPath,
  });

  /// Pushes new sampling settings onto the loaded model without reloading it.
  Future<void> applySettings(SamplerSettings settings);

  /// Constrains the next replies to [schema], a JSON Schema, or lifts the
  /// constraint when it is null.
  ///
  /// Forcing the shape rather than asking for it in the prompt is the whole
  /// reason structured answers are worth attempting on a phone-sized model: a
  /// 350M model will not reliably emit valid JSON because it was told to, but
  /// it cannot emit anything else when the sampler will not let it.
  ///
  /// Throws when the backend will not compile the schema. A caller that can
  /// carry on without the constraint should catch it — see `AgentRunner`.
  Future<void> setResponseSchema(Map<String, dynamic>? schema);

  /// Turns the model's reasoning block on or off.
  ///
  /// Only works where the chat template reads `enable_thinking`; on a template
  /// that does not, this throws. An agent run turns it off, because a model
  /// that reasons will often work an answer out while thinking and then state
  /// it rather than reaching for the tool it was given — which is the failure
  /// this app is built to measure, not one to cause.
  Future<void> setThinking(bool enabled);

  /// Replaces the model's system prompt without reloading it.
  ///
  /// Separate from [applySettings] because the two have different owners: the
  /// sampler settings carry the user's own Chat prompt, while an agent brings
  /// the one written into its template, which is what makes it behave as the
  /// template intends. Unlike history, the system prompt survives
  /// [resetHistory] — it lives outside the transcript — so a run sets it once.
  Future<void> setSystemPrompt(String prompt);

  /// Replaces the model's context with a restored transcript, so a session
  /// reopened after a restart continues rather than starting cold.
  Future<void> restoreHistory(List<ChatMessage> messages);

  /// Clears the model's context.
  Future<void> resetHistory();

  /// Replaces the tools the model may call. Pass an empty list to take them
  /// all away.
  ///
  /// Cheap, and deliberately separate from [load]: an agent changes the tool
  /// set before every step, and doing that by reloading the weights would cost
  /// seconds a step. Takes [ToolDefinition]s rather than anything from the
  /// backend, so nothing above this interface knows what runs underneath.
  Future<void> setTools(List<ToolDefinition> tools);

  /// The tool calls made since the context was last cleared, oldest first.
  ///
  /// Scoped by [resetHistory] rather than by a marker, which is why an agent
  /// resets between steps: it makes "recent" mean "this step's" with nothing
  /// to track.
  Future<List<ToolInvocation>> recentToolCalls();

  /// Streams the reply one token per event. [imagePaths] are sent ahead of
  /// [prompt], and need the model to have been loaded with a projector.
  Stream<String> ask(String prompt, {List<String> imagePaths});

  /// Asks the model to stop generating.
  void stop();

  /// Releases the model.
  Future<void> dispose();
}
