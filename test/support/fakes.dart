import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of the default flutter_riverpod export surface in 3.x.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_fonts/google_fonts.dart';
import 'package:model_scope_flutter/config/di/providers.dart';
import 'package:model_scope_flutter/config/theme/app_theme.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/agent_template.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/download_progress.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/hf_repo_summary.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/data/repositories/agent_repository.dart';
import 'package:model_scope_flutter/data/repositories/agent_run_repository.dart';
import 'package:model_scope_flutter/data/repositories/api_key_repository.dart';
import 'package:model_scope_flutter/data/repositories/app_settings_repository.dart';
import 'package:model_scope_flutter/data/repositories/catalog_repository.dart';
import 'package:model_scope_flutter/data/repositories/hugging_face_repository.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/data/repositories/session_repository.dart';
import 'package:model_scope_flutter/data/repositories/settings_repository.dart';
import 'package:model_scope_flutter/data/sources/secure_key_store.dart';
import 'package:model_scope_flutter/domain/services/app_cache_service.dart';
import 'package:model_scope_flutter/domain/services/attachment_picker.dart';
import 'package:model_scope_flutter/domain/services/image_store.dart';
import 'package:model_scope_flutter/domain/services/llm_service.dart';
import 'package:model_scope_flutter/domain/services/model_downloader.dart';
import 'package:model_scope_flutter/domain/tools/tool_definition.dart';
import 'package:model_scope_flutter/domain/tools/tool_registry.dart';

/// An [LlmService] that replays canned tokens instead of running a model. It
/// records every call, so a test can assert the max-token cap reached [stop].
class FakeLlmService implements LlmService {
  FakeLlmService({
    this.tokens = const <String>['Hello', ' ', 'world'],
    this.gap = Duration.zero,
    this.failure,
  });

  /// Emitted one per stream event, exactly as `nobodywho` does.
  List<String> tokens;

  /// Delay before each token, used to make the latency figure measurable.
  Duration gap;

  /// Thrown instead of streaming, to exercise the failure path.
  Object? failure;

  /// Thrown by [load] instead of loading, or null to let it succeed. Takes the
  /// runtime settings so a test can refuse one configuration and accept
  /// another, which is how the GPU-to-CPU fallback is exercised.
  Object? Function(AppSettings runtime)? loadFailure;

  /// Set to hold [load] open, so the `preparing` state can be observed.
  Completer<void>? loadGate;

  final List<String> prompts = <String>[];

  /// The images handed to each [ask], one entry per call alongside [prompts].
  final List<List<String>> askedImages = <List<String>>[];

  /// The projector path each [load] was given, null entries included.
  final List<String?> projectors = <String?>[];

  /// Replies handed out in order, one per [ask], falling back to [tokens] once
  /// the list runs out. Lets an agent test give each step its own answer.
  List<List<String>>? scriptedReplies;

  /// What [recentToolCalls] reports, keyed by the call number of the [ask] it
  /// follows. An entry missing means that step called nothing.
  Map<int, List<ToolInvocation>> scriptedToolCalls =
      <int, List<ToolInvocation>>{};

  /// The tool names given to each [setTools], one entry per call — so a test
  /// can check a step was handed exactly one tool.
  final List<List<String>> toolSets = <List<String>>[];

  /// Every prompt handed to [setSystemPrompt], so a test can prove an agent's
  /// own prompt reached the model and was set once rather than per step.
  final List<String> systemPrompts = <String>[];

  /// Every value handed to [setThinking].
  final List<bool> thinkingCalls = <bool>[];

  /// Thrown by [setThinking] instead of recording, standing in for a chat
  /// template that does not read `enable_thinking`.
  Object? thinkingFailure;

  /// Bumped by [resetHistory], so a test can prove the context is cleared
  /// between steps.
  int resetCalls = 0;

  /// Set to make the next [ask] fail, for the partial-trace path.
  Object? Function(int askNumber)? askFailure;

  int _asks = 0;

  final List<SamplerSettings> applied = <SamplerSettings>[];
  final List<AppSettings> runtimes = <AppSettings>[];
  final List<List<ChatMessage>> restored = <List<ChatMessage>>[];
  int stopCalls = 0;
  int loadCalls = 0;
  int disposeCalls = 0;

  /// How many tokens the last [ask] actually yielded before being abandoned.
  int emitted = 0;

  bool _stopped = false;
  bool _loaded = false;
  String? _loadedModelId;
  String? _loadedProjectorPath;

  @override
  bool get isLoaded => _loaded;

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
    loadCalls++;
    applied.add(settings);
    runtimes.add(runtime);
    projectors.add(projectorPath);
    await loadGate?.future;

    final refusal = loadFailure?.call(runtime);
    if (refusal != null) throw refusal;

    _loaded = true;
    _loadedModelId = model.id;
    _loadedProjectorPath = projectorPath;
  }

  /// Marks weights as loaded without going through [load]. An agent run needs
  /// a loaded model but does not load one itself — that is the view model's
  /// job — so its tests start from here.
  void loadedForTest([String id = 'qwen25-15b']) {
    _loaded = true;
    _loadedModelId = id;
  }

  @override
  Future<void> applySettings(SamplerSettings settings) async =>
      applied.add(settings);

  @override
  Future<void> setSystemPrompt(String prompt) async =>
      systemPrompts.add(prompt);

  @override
  Future<void> setThinking(bool enabled) async {
    final refusal = thinkingFailure;
    if (refusal != null) throw refusal;
    thinkingCalls.add(enabled);
  }

  @override
  Future<void> restoreHistory(List<ChatMessage> messages) async =>
      restored.add(List<ChatMessage>.unmodifiable(messages));

  @override
  Future<void> resetHistory() async => resetCalls++;

  @override
  Future<void> setTools(List<ToolDefinition> tools) async =>
      toolSets.add(<String>[for (final tool in tools) tool.name]);

  @override
  Future<List<ToolInvocation>> recentToolCalls() async =>
      scriptedToolCalls[_asks - 1] ?? const <ToolInvocation>[];

  @override
  Stream<String> ask(
    String prompt, {
    List<String> imagePaths = const <String>[],
  }) async* {
    final askNumber = _asks++;
    prompts.add(prompt);
    askedImages.add(List<String>.unmodifiable(imagePaths));
    _stopped = false;
    emitted = 0;

    final Object? error = failure ?? askFailure?.call(askNumber);
    if (error != null) throw error;

    final scripted = scriptedReplies;
    final reply = scripted != null && askNumber < scripted.length
        ? scripted[askNumber]
        : tokens;

    for (final token in reply) {
      if (_stopped) return;
      if (gap > Duration.zero) await Future<void>.delayed(gap);
      emitted++;
      yield token;
    }
  }

  @override
  void stop() {
    stopCalls++;
    _stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _loaded = false;
    _loadedModelId = null;
  }
}

/// A [SessionRepository] held in memory, with a count of writes so a test can
/// tell a render from a commit.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository([List<ChatSession>? seed])
    : stored = List<ChatSession>.of(seed ?? const <ChatSession>[]);

  List<ChatSession> stored;
  int saveCalls = 0;

  @override
  Future<List<ChatSession>> load() async => List<ChatSession>.of(stored);

  @override
  Future<void> save(List<ChatSession> sessions) async {
    saveCalls++;
    stored = List<ChatSession>.of(sessions);
  }
}

/// A [SettingsRepository] held in memory.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository([this.stored = const SamplerSettings()]);

  SamplerSettings stored;
  int saveCalls = 0;

  @override
  Future<SamplerSettings> load() async => stored;

  @override
  Future<void> save(SamplerSettings settings) async {
    saveCalls++;
    stored = settings;
  }
}

/// An [AttachmentPicker] that returns a fixed path without touching a dialog.
/// Pass a list to hand back a different one per call, which is how the
/// three-image cap is reached.
class FakeAttachmentPicker implements AttachmentPicker {
  FakeAttachmentPicker([String? result])
    : results = result == null ? const <String>[] : <String>[result];

  FakeAttachmentPicker.each(this.results);

  final List<String> results;
  int calls = 0;

  @override
  Future<String?> pick() async {
    final index = calls++;
    if (results.isEmpty) return null;
    // The last entry repeats, so a one-path fake answers every call.
    return results[index < results.length ? index : results.length - 1];
  }
}

/// An [ImageStore] that hands back a path under a notional app directory
/// without copying anything, so widget tests never touch the disk.
class FakeImageStore implements ImageStore {
  static const String root = '/app/images';

  final List<String> saved = <String>[];
  final List<String> deleted = <String>[];

  /// Set to make [save] fail, exercising the unreadable-source path.
  bool refuse = false;

  @override
  Future<String?> save(String sourcePath) async {
    if (refuse) return null;
    final name = sourcePath.split(RegExp(r'[\\/]')).last;
    final stored = '$root/${saved.length}-$name';
    saved.add(stored);
    return stored;
  }

  @override
  Future<void> delete(Iterable<String> paths) async =>
      deleted.addAll(paths.where((path) => path.startsWith(root)));
}

/// A [ModelLibraryRepository] held in memory.
class FakeModelLibraryRepository implements ModelLibraryRepository {
  FakeModelLibraryRepository([this.stored = ModelLibrary.empty]);

  /// Seeds a library holding [models], with the first one active, and
  /// optionally the [projectors] that give them vision.
  FakeModelLibraryRepository.of(
    List<ModelDescriptor> models, {
    List<ProjectorDescriptor> projectors = const <ProjectorDescriptor>[],
  }) : stored = ModelLibrary(
         models: models,
         projectors: projectors,
         activeId: models.isEmpty ? null : models.first.id,
       );

  ModelLibrary stored;
  int saveCalls = 0;

  @override
  Future<ModelLibrary> load() async => stored;

  @override
  Future<void> save(ModelLibrary library) async {
    saveCalls++;
    stored = library;
  }
}

/// An [AgentRepository] holding templates in memory instead of reading the
/// asset bundle and the documents directory.
class FakeAgentRepository implements AgentRepository {
  FakeAgentRepository([List<Agent>? seed]) : stored = <Agent>[...?seed];

  /// Built-ins, as the bench receives them.
  FakeAgentRepository.builtIn(List<AgentTemplate> templates)
    : stored = <Agent>[
        for (final template in templates)
          Agent(template: template, isBuiltIn: true),
      ];

  List<Agent> stored;
  final List<AgentTemplate> saved = <AgentTemplate>[];
  final List<String> deleted = <String>[];

  @override
  Future<List<Agent>> load() async => stored;

  @override
  Future<Agent?> byId(String id) async {
    for (final agent in stored) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  @override
  Future<bool> save(AgentTemplate template) async {
    saved.add(template);
    return true;
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

/// An [AgentRunRepository] held in memory, newest first as the real one keeps
/// it.
class FakeAgentRunRepository implements AgentRunRepository {
  FakeAgentRunRepository([List<AgentRun>? seed])
    : stored = <AgentRun>[...?seed];

  List<AgentRun> stored;

  @override
  Future<List<AgentRun>> load() async => stored;

  @override
  Future<void> add(AgentRun run) async => stored = <AgentRun>[run, ...stored];

  @override
  Future<void> save(List<AgentRun> runs) async => stored = runs;

  @override
  Future<AgentRun?> lastRunOf(String agentId) async {
    for (final run in stored) {
      if (run.agentId == agentId) return run;
    }
    return null;
  }
}

/// An [AppSettingsRepository] held in memory.
class FakeAppSettingsRepository implements AppSettingsRepository {
  FakeAppSettingsRepository([this.stored = const AppSettings()]);

  AppSettings stored;
  int saveCalls = 0;

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async {
    saveCalls++;
    stored = settings;
  }
}

/// A [SecureKeyStore] that keeps secrets in a map instead of the keychain,
/// which has no implementation under `flutter test`.
class FakeSecureKeyStore implements SecureKeyStore {
  FakeSecureKeyStore([Map<String, String>? seed])
    : stored = <String, String>{...?seed};

  final Map<String, String> stored;

  @override
  Future<String?> read(String key) async => stored[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      stored.remove(key);
      return;
    }
    stored[key] = value;
  }
}

/// An [ApiKeyRepository] held in memory.
class FakeApiKeyRepository implements ApiKeyRepository {
  FakeApiKeyRepository([Map<ApiKeyKind, String>? seed])
    : stored = <ApiKeyKind, String>{...?seed};

  final Map<ApiKeyKind, String> stored;
  int writeCalls = 0;

  @override
  Future<Map<ApiKeyKind, String>> loadAll() async => <ApiKeyKind, String>{
    for (final kind in ApiKeyKind.values) kind: stored[kind] ?? '',
  };

  @override
  Future<String> read(ApiKeyKind kind) async => stored[kind] ?? '';

  @override
  Future<void> write(ApiKeyKind kind, String value) async {
    writeCalls++;
    stored[kind] = value.trim();
  }
}

/// A [CatalogRepository] that serves a canned manifest.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({List<CatalogModel>? models, this.failure})
    : models = models ?? <CatalogModel>[fakeCatalogModel()];

  List<CatalogModel> models;

  /// Thrown by [load], for the catalog screen's error state.
  Object? failure;

  int loadCalls = 0;

  @override
  Future<List<CatalogModel>> load() async {
    loadCalls++;

    final Object? error = failure;
    if (error != null) throw error;

    return models;
  }
}

/// A [HuggingFaceRepository] that serves canned stats and file trees.
class FakeHuggingFaceRepository implements HuggingFaceRepository {
  FakeHuggingFaceRepository({
    this.details = const <String, HfRepoSummary>{},
    this.files = const <String, List<GgufFile>>{},
    this.account = 'octocat',
    this.failure,
    this.filesFailure,
  });

  /// Stats per repository id. A repository with no entry gets [fakeRepo].
  Map<String, HfRepoSummary> details;

  Map<String, List<GgufFile>> files;

  /// What `verifyToken` returns.
  String account;

  /// Thrown by [detailsOf] and [verifyToken].
  Object? failure;

  /// Thrown by [filesOf], so the model sheet's error state can be exercised on
  /// its own while the catalog behind it still renders.
  Object? filesFailure;

  final List<String> detailRequests = <String>[];
  final List<String> fileRequests = <String>[];
  final List<String> verified = <String>[];

  @override
  Future<HfRepoSummary> detailsOf(String repoId) async {
    detailRequests.add(repoId);

    final Object? error = failure;
    if (error != null) throw error;

    return details[repoId] ?? fakeRepo(id: repoId);
  }

  @override
  Future<List<GgufFile>> filesOf(String repoId) async {
    fileRequests.add(repoId);

    final Object? error = filesFailure;
    if (error != null) throw error;

    return files[repoId] ?? const <GgufFile>[];
  }

  @override
  Future<String> verifyToken(String token) async {
    verified.add(token);

    final Object? error = failure;
    if (error != null) throw error;

    return account;
  }
}

/// A [ModelDownloader] the test drives by hand. A transfer belongs to the
/// platform and reports on one long-lived stream, so a test says what the
/// platform did with [emit] rather than queueing events up front.
class FakeModelDownloader implements ModelDownloader {
  FakeModelDownloader({this.restored = const <String, DownloadProgress>{}});

  static const String downloadedPath = '/cache/model.gguf';

  /// Returned by [restore], standing in for transfers that outlived the app.
  Map<String, DownloadProgress> restored;

  /// Thrown by [restore], so the view model's recovery path can be exercised.
  Object? restoreFailure;

  final List<GgufFile> started = <GgufFile>[];
  final List<String> displayNames = <String>[];
  final List<String?> tokens = <String?>[];
  final List<String> pauses = <String>[];
  final List<String> resumes = <String>[];
  final List<String> cancels = <String>[];
  int restoreCalls = 0;
  int disposeCalls = 0;
  int notifyAsks = 0;

  final StreamController<DownloadUpdate> _updates =
      StreamController<DownloadUpdate>.broadcast();

  @override
  Stream<DownloadUpdate> get updates => _updates.stream;

  /// Reports progress for [id], as the platform would.
  void emit(String id, DownloadProgress progress) {
    if (_updates.isClosed) return;
    _updates.add((id, progress));
  }

  @override
  Future<Map<String, DownloadProgress>> restore() async {
    restoreCalls++;

    final Object? error = restoreFailure;
    if (error != null) throw error;

    return restored;
  }

  @override
  Future<void> start({
    required GgufFile file,
    required String displayName,
    String? token,
  }) async {
    started.add(file);
    displayNames.add(displayName);
    tokens.add(token);
  }

  @override
  Future<void> pause(String id) async => pauses.add(id);

  @override
  Future<void> resume(String id) async => resumes.add(id);

  @override
  Future<void> cancel(String id) async => cancels.add(id);

  @override
  Future<void> askToNotify() async => notifyAsks++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _updates.close();
  }
}

/// An [AppCacheService] that reports a fixed size instead of reading the disk.
/// `pump` runs inside a fake-async zone where real file I/O never completes, so
/// the real service would leave the Storage card spinning forever. That one is
/// covered in `app_cache_service_test.dart`.
class FakeAppCacheService implements AppCacheService {
  FakeAppCacheService([this.bytes = 0]);

  int bytes;
  int clearCalls = 0;

  @override
  Future<int> sizeInBytes() async => bytes;

  @override
  Future<void> clear() async {
    clearCalls++;
    bytes = 0;
  }
}

/// The overrides every test needs: fakes in place of disk, keychain, network
/// and native code.
List<Override> fakeOverrides({
  required FakeLlmService llm,
  required FakeSessionRepository sessions,
  FakeSettingsRepository? settings,
  FakeAttachmentPicker? picker,
  FakeImageStore? images,
  FakeModelLibraryRepository? library,
  FakeAppSettingsRepository? appSettings,
  FakeApiKeyRepository? apiKeys,
  FakeHuggingFaceRepository? huggingFace,
  FakeCatalogRepository? catalog,
  FakeModelDownloader? downloader,
  FakeAppCacheService? cache,
  FakeAgentRepository? agents,
  FakeAgentRunRepository? agentRuns,
  ToolRegistry? tools,
}) => <Override>[
  documentsDirectoryProvider.overrideWithValue(Directory.systemTemp),
  sessionRepositoryProvider.overrideWithValue(sessions),
  settingsRepositoryProvider.overrideWithValue(
    settings ?? FakeSettingsRepository(),
  ),
  llmServiceProvider.overrideWithValue(llm),
  attachmentPickerProvider.overrideWithValue(
    picker ?? FakeAttachmentPicker('photo.jpg'),
  ),
  imageStoreProvider.overrideWithValue(images ?? FakeImageStore()),
  // One model installed by default: that is the ordinary state of the app,
  // and the empty library is a distinct case tests opt into deliberately.
  modelLibraryRepositoryProvider.overrideWithValue(
    library ??
        FakeModelLibraryRepository.of(<ModelDescriptor>[fakeInstalledModel()]),
  ),
  appSettingsRepositoryProvider.overrideWithValue(
    appSettings ?? FakeAppSettingsRepository(),
  ),
  apiKeyRepositoryProvider.overrideWithValue(apiKeys ?? FakeApiKeyRepository()),
  huggingFaceRepositoryProvider.overrideWithValue(
    huggingFace ?? FakeHuggingFaceRepository(),
  ),
  // The real one reads an asset, which `flutter test` can serve but only after
  // the bundle is primed; a fake keeps every test off that path.
  catalogRepositoryProvider.overrideWithValue(
    catalog ?? FakeCatalogRepository(),
  ),
  modelDownloaderProvider.overrideWithValue(
    downloader ?? FakeModelDownloader(),
  ),
  appCacheServiceProvider.overrideWithValue(cache ?? FakeAppCacheService()),
  // Overridden even where a test has no interest in agents: the real one
  // enumerates the asset bundle, which `flutter test` serves only once primed.
  agentRepositoryProvider.overrideWithValue(agents ?? FakeAgentRepository()),
  agentRunRepositoryProvider.overrideWithValue(
    agentRuns ?? FakeAgentRunRepository(),
  ),
  toolRegistryProvider.overrideWithValue(tools ?? fakeToolRegistry()),
];

/// A registry of tools that do nothing, named as the bundled agents name them.
/// The runner never calls a tool itself — the model does, inside the backend —
/// so a stand-in with the right name is all an agent test needs.
///
/// [needingKeys] are reported unready, which is what puts the amber
/// `Needs Tavily key` line on a bench card.
ToolRegistry fakeToolRegistry({
  List<String> names = const <String>[
    'web_search',
    'read_web_page',
    'calculator',
    'date_math',
    'unit_convert',
  ],
  List<String> needingKeys = const <String>[],
}) => ToolRegistry(
  tools: <ToolDefinition>[
    for (final name in names)
      ToolDefinition(
        name: name,
        description: 'Does nothing, for a test.',
        function: ({required String input}) async => 'ok',
      ),
  ],
  readiness: <String, Future<bool> Function()>{
    for (final name in needingKeys) name: () async => false,
  },
  blockers: <String, ToolBlocker>{
    for (final name in needingKeys)
      name: 'Needs $name key — set it in Settings',
  },
);

/// One agent template, with a single tool step and an answer — the shape every
/// bundled agent has, minus the prose.
AgentTemplate fakeAgentTemplate({
  String id = 'test_agent',
  String name = 'Test Agent',
  String purpose = 'For a test',
  String description = 'A test agent that searches and then answers.',
  String icon = 'search',
  String systemPrompt = 'You are careful.',
  List<AgentInput>? inputs,
  List<PipelineStep>? pipeline,
  AnswerStep? answer,
}) => AgentTemplate(
  id: id,
  name: name,
  purpose: purpose,
  description: description,
  icon: icon,
  systemPrompt: systemPrompt,
  inputs:
      inputs ??
      const <AgentInput>[
        AgentInput(name: 'query', label: 'Query', defaultValue: 'dart records'),
      ],
  pipeline:
      pipeline ??
      const <PipelineStep>[
        PipelineStep(
          id: 'search',
          kind: StepKind.tool,
          tool: 'web_search',
          prompt: 'Search for {{input.query}}.',
        ),
      ],
  answer:
      answer ??
      const AnswerStep(
        prompt: 'Answer from the search results.',
        reads: <String>['step.search'],
      ),
);

/// A catalog saying the model [fakeInstalledModel] installs can call tools.
///
/// The shared [fakeCatalogModel] default is text-only and shares a repository
/// id with it, so an agent test that does not pass this would see the "not
/// marked as tool-calling" warning in every case.
FakeCatalogRepository toolCapableCatalog() => FakeCatalogRepository(
  models: <CatalogModel>[
    fakeCatalogModel(
      capabilities: const <ModelCapability>[
        ModelCapability.textToText,
        ModelCapability.toolCalling,
      ],
    ),
  ],
);

/// What [FakeLlmService.scriptedToolCalls] needs for the tool step of
/// [fakeAgentTemplate] to call its tool on the ask numbered [onAsk].
///
/// The default of 0 means no retry happens, so a test about something other
/// than retrying sees one ask per step.
Map<int, List<ToolInvocation>> toolCalledOn({
  int onAsk = 0,
  String name = 'web_search',
  String arguments = '"dart records"',
  String result = 'Results for dart records',
}) => <int, List<ToolInvocation>>{
  onAsk: <ToolInvocation>[
    ToolInvocation(name: name, arguments: arguments, result: result),
  ],
};

/// One finished run, as the history card and the bench footer read it.
AgentRun fakeAgentRun({
  String id = 'run-1',
  String agentId = 'test_agent',
  String agentName = 'Test Agent',
  String modelId = 'smollm2-360m',
  DateTime? startedAt,
  int durationMs = 4240,
  List<TraceEntry>? trace,
  String output = 'Dart records are tuples with named fields.',
  String? error,
}) => AgentRun(
  id: id,
  agentId: agentId,
  agentName: agentName,
  modelId: modelId,
  startedAt: startedAt ?? DateTime(2026, 10, 6, 9),
  durationMs: durationMs,
  trace:
      trace ??
      const <TraceEntry>[
        TraceEntry(
          kind: TraceKind.tool,
          label: 'web_search("dart records")',
          durationMs: 1060,
        ),
        TraceEntry(
          kind: TraceKind.answer,
          label: 'Final answer',
          durationMs: 2200,
        ),
      ],
  output: output,
  error: error,
);

/// Turns off Riverpod 3's automatic retry of a failed provider build. By
/// default a failed build retries on a timer, so a test asserting the failure
/// waits on a value that never settles. Pass as
/// `ProviderContainer.test(retry: noRetry)` whenever a fake is scripted to
/// throw.
Duration? noRetry(int retryCount, Object error) => null;

/// Wraps [child] in the app's theme and a [ProviderScope] holding [overrides].
/// Pass [noRetry] as [retry] whenever a fake is scripted to throw, or a backoff
/// timer is left running when the test ends.
Widget harness(
  Widget child, {
  List<Override> overrides = const [],
  Duration? Function(int retryCount, Object error)? retry,
}) => ProviderScope(
  overrides: overrides,
  retry: retry,
  child: MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: child,
  ),
);

/// Stops `google_fonts` reaching for the network, which is neither available
/// nor deterministic under `flutter test`.
void useBundledFontsOnly() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// An installed model, standing in for the hardcoded descriptor the app used
/// to ship. [localPath] points at a file that does not exist, which is what a
/// test wants: removing the model must not delete anything real.
ModelDescriptor fakeInstalledModel({
  String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  String fileName = 'smollm2-360m-instruct-q8_0.gguf',
  String name = 'SmolLM2 360M Instruct',
  String quantization = 'Q8_0',
  int sizeBytes = 399 * 1000 * 1000,
  String? localPath,
  String? paramLabel = '360M',
}) => ModelDescriptor(
  repoId: repoId,
  fileName: fileName,
  name: name,
  quantization: quantization,
  sizeBytes: sizeBytes,
  localPath: localPath ?? '/cache/$fileName',
  installedAt: DateTime(2026, 9, 30, 12),
  paramLabel: paramLabel,
);

/// An installed projector for [repoId], defaulting to the repository
/// [fakeInstalledModel] comes from — so the pair gives that model vision.
/// [localPath] points at nothing real, for the same reason.
ProjectorDescriptor fakeProjector({
  String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  String fileName = 'mmproj-BF16.gguf',
  int sizeBytes = 310 * 1000 * 1000,
  String? localPath,
}) => ProjectorDescriptor(
  repoId: repoId,
  fileName: fileName,
  sizeBytes: sizeBytes,
  localPath: localPath ?? '/cache/$fileName',
  installedAt: DateTime(2026, 10, 5, 12),
);

/// One entry of the shipped manifest, as the catalog screen receives it.
CatalogModel fakeCatalogModel({
  String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  String name = 'SmolLM2 360M Instruct',
  String description = 'A small instruction model for quick local tests.',
  String? paramLabel = '360M',
  List<ModelCapability> capabilities = const <ModelCapability>[
    ModelCapability.textToText,
  ],
}) => CatalogModel(
  repoId: repoId,
  name: name,
  description: description,
  capabilities: capabilities,
  paramLabel: paramLabel,
);

/// The live stats behind one catalog card.
HfRepoSummary fakeRepo({
  String id = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  int downloads = 182000,
  int likes = 412,
  List<String> fileNames = const <String>['smollm2-360m-instruct-q8_0.gguf'],
}) => HfRepoSummary(
  id: id,
  downloads: downloads,
  likes: likes,
  siblings: <RepoSibling>[
    for (final name in fileNames) RepoSibling(rfilename: name),
  ],
);

/// One file inside [repoId]. Weights unless [kind] says otherwise.
GgufFile fakeGgufFile({
  String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  String fileName = 'smollm2-360m-instruct-q8_0.gguf',
  int sizeBytes = 399 * 1000 * 1000,
  GgufFileKind kind = GgufFileKind.model,
}) => GgufFile(
  repoId: repoId,
  fileName: fileName,
  sizeBytes: sizeBytes,
  kind: kind,
);

/// A session with [count] alternating turns, newest last.
ChatSession sessionWith({
  String id = 'session-1',
  String title = 'New chat',
  int count = 0,
  String? modelId,
}) {
  final start = DateTime(2026, 9, 30, 12);
  return ChatSession(
    id: id,
    title: title,
    modelId: modelId ?? fakeInstalledModel().id,
    createdAt: start,
    updatedAt: start,
    messages: <ChatMessage>[
      for (var i = 0; i < count; i++)
        ChatMessage(
          id: 'm$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: i.isEven ? 'Question $i' : 'Answer $i',
          createdAt: start.add(Duration(minutes: i)),
        ),
    ],
  );
}
