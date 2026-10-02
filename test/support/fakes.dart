import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of the default flutter_riverpod export surface in 3.x.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_fonts/google_fonts.dart';
import 'package:model_scope_flutter/config/di/providers.dart';
import 'package:model_scope_flutter/config/theme/app_theme.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/hf_repo_summary.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/data/repositories/api_key_repository.dart';
import 'package:model_scope_flutter/data/repositories/app_settings_repository.dart';
import 'package:model_scope_flutter/data/repositories/hugging_face_repository.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/data/repositories/session_repository.dart';
import 'package:model_scope_flutter/data/repositories/settings_repository.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';
import 'package:model_scope_flutter/data/sources/secure_key_store.dart';
import 'package:model_scope_flutter/domain/services/app_cache_service.dart';
import 'package:model_scope_flutter/domain/services/attachment_picker.dart';
import 'package:model_scope_flutter/domain/services/llm_service.dart';
import 'package:model_scope_flutter/domain/services/model_downloader.dart';

/// An [LlmService] that replays canned tokens instead of running a model.
///
/// It records every call so a test can assert that the max-token cap actually
/// reached [stop], which is the only thing enforcing the cap.
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

  /// Thrown by [load] instead of loading, or null to let it succeed.
  ///
  /// Takes the runtime settings so a test can refuse one configuration and
  /// accept another — which is how the GPU-to-CPU fallback is exercised.
  Object? Function(AppSettings runtime)? loadFailure;

  /// Set to hold [load] open, so the `preparing` state can be observed.
  Completer<void>? loadGate;

  final List<String> prompts = <String>[];
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

  @override
  bool get isLoaded => _loaded;

  @override
  String? get loadedModelId => _loadedModelId;

  @override
  Future<void> load({
    required ModelDescriptor model,
    required SamplerSettings settings,
    required AppSettings runtime,
  }) async {
    loadCalls++;
    applied.add(settings);
    runtimes.add(runtime);
    await loadGate?.future;

    final refusal = loadFailure?.call(runtime);
    if (refusal != null) throw refusal;

    _loaded = true;
    _loadedModelId = model.id;
  }

  @override
  Future<void> applySettings(SamplerSettings settings) async =>
      applied.add(settings);

  @override
  Future<void> restoreHistory(List<ChatMessage> messages) async =>
      restored.add(List<ChatMessage>.unmodifiable(messages));

  @override
  Future<void> resetHistory() async {}

  @override
  Stream<String> ask(String prompt) async* {
    prompts.add(prompt);
    _stopped = false;
    emitted = 0;

    final Object? error = failure;
    if (error != null) throw error;

    for (final token in tokens) {
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

/// An [AttachmentPicker] that returns a fixed name without touching a dialog.
class FakeAttachmentPicker implements AttachmentPicker {
  FakeAttachmentPicker([this.result]);

  final String? result;
  final List<AttachmentKind> kinds = <AttachmentKind>[];

  @override
  Future<String?> pick(AttachmentKind kind) async {
    kinds.add(kind);
    return result;
  }
}

/// A [ModelLibraryRepository] held in memory.
class FakeModelLibraryRepository implements ModelLibraryRepository {
  FakeModelLibraryRepository([this.stored = ModelLibrary.empty]);

  /// Seeds a library holding [models], with the first one active.
  FakeModelLibraryRepository.of(List<ModelDescriptor> models)
    : stored = ModelLibrary(
        models: models,
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

/// A [HuggingFaceRepository] that serves canned pages and file trees.
///
/// Cursors are page indices as strings: a page whose `nextCursor` is `'1'` is
/// followed by `pages[1]`. That keeps the pagination tests readable without
/// reproducing the Hub's opaque cursor format, which the client already covers.
class FakeHuggingFaceRepository implements HuggingFaceRepository {
  FakeHuggingFaceRepository({
    this.pages = const <HfRepoPage>[],
    this.files = const <String, List<GgufFile>>{},
    this.account = 'octocat',
    this.failure,
    this.filesFailure,
  });

  List<HfRepoPage> pages;
  Map<String, List<GgufFile>> files;

  /// What `verifyToken` returns.
  String account;

  /// Thrown by [search] instead of returning a page.
  Object? failure;

  /// Thrown by [filesOf], so the chip-row error state can be exercised on its
  /// own while the surrounding list still renders.
  Object? filesFailure;

  final List<({CatalogSort sort, String query, String? cursor})> searches =
      <({CatalogSort sort, String query, String? cursor})>[];
  final List<String> fileRequests = <String>[];
  final List<String> verified = <String>[];

  @override
  Future<HfRepoPage> search({
    required CatalogSort sort,
    required String query,
    String? cursor,
  }) async {
    searches.add((sort: sort, query: query, cursor: cursor));

    final Object? error = failure;
    if (error != null) throw error;

    final index = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    if (index >= pages.length) return HfRepoPage.empty;
    return pages[index];
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

/// A [ModelDownloader] that replays scripted progress instead of fetching.
class FakeModelDownloader implements ModelDownloader {
  FakeModelDownloader({List<DownloadProgress>? script})
    : script =
          script ??
          <DownloadProgress>[
            const Downloading(received: 50, total: 100),
            const DownloadCompleted(_downloadedPath),
          ];

  static const String _downloadedPath = '/cache/model.gguf';

  /// Emitted in order, then the stream closes.
  List<DownloadProgress> script;

  /// Set to drive progress by hand, for tests that need to observe an
  /// in-flight download rather than its outcome. Takes precedence over
  /// [script]; the test owns closing it.
  StreamController<DownloadProgress>? controller;

  final List<String> urls = <String>[];
  final List<String?> tokens = <String?>[];

  @override
  Stream<DownloadProgress> download({required String url, String? token}) {
    urls.add(url);
    tokens.add(token);

    final manual = controller;
    if (manual != null) return manual.stream;
    return Stream<DownloadProgress>.fromIterable(script);
  }
}

/// An [AppCacheService] that reports a fixed size instead of reading the disk.
///
/// Not just for determinism: `pump` runs inside a fake-async zone where real
/// file I/O never completes, so a widget test holding the real service would
/// leave the Storage card's indeterminate bar spinning and `pumpAndSettle`
/// would never return. The real one is covered in `app_cache_service_test.dart`.
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
  FakeModelLibraryRepository? library,
  FakeAppSettingsRepository? appSettings,
  FakeApiKeyRepository? apiKeys,
  FakeHuggingFaceRepository? huggingFace,
  FakeModelDownloader? downloader,
  FakeAppCacheService? cache,
}) => <Override>[
  documentsDirectoryProvider.overrideWithValue(Directory.systemTemp),
  sessionRepositoryProvider.overrideWithValue(sessions),
  settingsRepositoryProvider.overrideWithValue(
    settings ?? FakeSettingsRepository(),
  ),
  llmServiceProvider.overrideWithValue(llm),
  attachmentPickerProvider.overrideWithValue(
    picker ?? FakeAttachmentPicker('report.pdf'),
  ),
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
  modelDownloaderProvider.overrideWithValue(
    downloader ?? FakeModelDownloader(),
  ),
  appCacheServiceProvider.overrideWithValue(cache ?? FakeAppCacheService()),
];

/// Turns off Riverpod 3's automatic retry of a failed provider build.
///
/// By default a provider whose `build` throws stays in `AsyncLoading` holding
/// the error and retries on a timer. That is reasonable at runtime, but a test
/// asserting the failure would be waiting on a value that never settles — so
/// pass this as `ProviderContainer.test(retry: noRetry)` whenever the fake is
/// scripted to throw.
Duration? noRetry(int retryCount, Object error) => null;

/// Wraps [child] in the app's theme and a [ProviderScope] holding [overrides].
Widget harness(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
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

/// A catalog row, as the browse sheet receives it.
HfRepoSummary fakeRepo({
  String id = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  int downloads = 182000,
  int likes = 412,
  List<String> tags = const <String>['gguf', 'text-generation'],
}) => HfRepoSummary(
  id: id,
  downloads: downloads,
  likes: likes,
  tags: tags,
  createdAt: DateTime(2026, 1, 1),
);

/// One downloadable quant inside [repoId].
GgufFile fakeGgufFile({
  String repoId = 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
  String fileName = 'smollm2-360m-instruct-q8_0.gguf',
  int sizeBytes = 399 * 1000 * 1000,
}) => GgufFile(repoId: repoId, fileName: fileName, sizeBytes: sizeBytes);

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
