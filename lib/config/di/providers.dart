import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/api_keys.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/agent_repository.dart';
import '../../data/repositories/agent_run_repository.dart';
import '../../data/repositories/api_key_repository.dart';
import '../../data/repositories/app_settings_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/hugging_face_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/model_library_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/agent_asset_source.dart';
import '../../data/sources/agent_file_store.dart';
import '../../data/sources/firecrawl_api_client.dart';
import '../../data/sources/hf_api_client.dart';
import '../../data/sources/json_file_store.dart';
import '../../data/sources/secure_key_store.dart';
import '../../data/sources/tavily_api_client.dart';
import '../../domain/services/agent_runner.dart';
import '../../domain/services/agent_validator.dart';
import '../../domain/services/app_cache_service.dart';
import '../../domain/services/attachment_picker.dart';
import '../../domain/services/firecrawl_web_crawler_service.dart';
import '../../domain/services/image_store.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/model_downloader.dart';
import '../../domain/services/nobodywho_llm_service.dart';
import '../../domain/services/tavily_web_search_service.dart';
import '../../domain/tools/tool_definition.dart';
import '../../domain/tools/tool_registry.dart';
import '../../domain/tools/web_tools.dart';
import '../router/app_router.dart';
import 'view_models.dart';

final documentsDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'documentsDirectoryProvider must be overridden in ProviderScope.',
  ),
);

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (ref) => SharedPreferencesAsync(),
);

final sessionStoreProvider = Provider<JsonFileStore>(
  (ref) => JsonFileStore(
    directory: ref.watch(documentsDirectoryProvider),
    fileName: 'sessions.json',
  ),
);

final settingsStoreProvider = Provider<JsonFileStore>(
  (ref) => JsonFileStore(
    directory: ref.watch(documentsDirectoryProvider),
    fileName: 'settings.json',
  ),
);

final modelStoreProvider = Provider<JsonFileStore>(
  (ref) => JsonFileStore(
    directory: ref.watch(documentsDirectoryProvider),
    fileName: 'models.json',
  ),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    ref.watch(sharedPreferencesProvider),
    LocalSessionRepository(ref.watch(sessionStoreProvider)),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(settingsStoreProvider)),
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(ref.watch(settingsStoreProvider)),
);

final modelLibraryRepositoryProvider = Provider<ModelLibraryRepository>(
  (ref) => ModelLibraryRepository(ref.watch(modelStoreProvider)),
);

/// Closed with the provider, so a disposed scope does not leak a socket pool.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const SecureKeyStore(),
);

final apiKeyRepositoryProvider = Provider<ApiKeyRepository>(
  (ref) => ApiKeyRepository(ref.watch(secureKeyStoreProvider)),
);

final hfApiClientProvider = Provider<HfApiClient>(
  (ref) => HfApiClient(ref.watch(httpClientProvider)),
);

final tavilyApiClientProvider = Provider<TavilyApiClient>(
  (ref) => TavilyApiClient(ref.watch(httpClientProvider)),
);

final firecrawlApiClientProvider = Provider<FirecrawlApiClient>(
  (ref) => FirecrawlApiClient(ref.watch(httpClientProvider)),
);

/// Searching the web. Like the Hugging Face repository, the key is read per
/// call, so one pasted into Settings works on the next search.
final webSearchServiceProvider = Provider<TavilyWebSearchService>(
  (ref) => TavilyWebSearchService(
    ref.watch(tavilyApiClientProvider),
    () => ref.read(apiKeyRepositoryProvider).read(ApiKeyKind.tavily),
  ),
);

/// Reading one web page, on the same per-call key arrangement.
final webCrawlerServiceProvider = Provider<FirecrawlWebCrawlerService>(
  (ref) => FirecrawlWebCrawlerService(
    ref.watch(firecrawlApiClientProvider),
    () => ref.read(apiKeyRepositoryProvider).read(ApiKeyKind.firecrawl),
  ),
);

/// What a model is allowed to call. Backend-neutral: the agent flow turns
/// these into `nobodywho` tools with `toNobodyWhoTools` at the point it hands
/// them to a chat, which keeps the native dependency out of everything else.
///
/// The list is not filtered by whether a key is set. A tool whose key is
/// missing answers with a sentence saying so, which tells the model something
/// it can relay — whereas silently withholding the tool leaves it to invent an
/// answer instead.
final webToolsProvider = Provider<List<ToolDefinition>>(
  (ref) => webTools(
    search: ref.watch(webSearchServiceProvider),
    crawler: ref.watch(webCrawlerServiceProvider),
  ),
);

/// Every tool a template may name, and whether each can run right now. The
/// `TOOLS n registered` tile on the Agent bench counts this.
final toolRegistryProvider = Provider<ToolRegistry>(
  (ref) => ToolRegistry.standard(
    search: ref.watch(webSearchServiceProvider),
    crawler: ref.watch(webCrawlerServiceProvider),
  ),
);

/// The agents shipped in `assets/agents/`.
final agentAssetSourceProvider = Provider<AgentAssetSource>(
  (ref) => AgentAssetSource(),
);

/// Where a custom agent's own JSON file lives.
final agentFileStoreProvider = Provider<AgentFileStore>(
  (ref) => AgentFileStore(directory: ref.watch(documentsDirectoryProvider)),
);

final agentRepositoryProvider = Provider<AgentRepository>(
  (ref) => AgentRepository(
    ref.watch(agentAssetSourceProvider),
    ref.watch(agentFileStoreProvider),
  ),
);

final agentRunStoreProvider = Provider<JsonFileStore>(
  (ref) => JsonFileStore(
    directory: ref.watch(documentsDirectoryProvider),
    fileName: 'agent_runs.json',
  ),
);

final agentRunRepositoryProvider = Provider<AgentRunRepository>(
  (ref) => AgentRunRepository(ref.watch(agentRunStoreProvider)),
);

final agentValidatorProvider = Provider<AgentValidator>(
  (ref) => AgentValidator(ref.watch(toolRegistryProvider)),
);

/// The engine. It does not load the weights — the view model does, because
/// only it knows the runtime settings and the GPU-to-CPU fallback.
final agentRunnerProvider = Provider<AgentRunner>(
  (ref) => AgentRunner(
    ref.watch(llmServiceProvider),
    ref.watch(toolRegistryProvider),
    ref.watch(agentValidatorProvider),
  ),
);

/// The models this build offers, read from the manifest it ships with.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(),
);

/// The token is read per request rather than captured, so pasting one into the
/// API keys card takes effect on the next call without rebuilding anything.
final huggingFaceRepositoryProvider = Provider<HuggingFaceRepository>(
  (ref) => HuggingFaceRepository(
    ref.watch(hfApiClientProvider),
    () => ref.read(apiKeyRepositoryProvider).read(ApiKeyKind.huggingFace),
  ),
);

/// Disposed with the scope so the update subscription does not outlive it; the
/// downloads themselves carry on regardless, which is the point.
final modelDownloaderProvider = Provider<ModelDownloader>((ref) {
  final downloader = ModelDownloader();
  ref.onDispose(downloader.dispose);
  return downloader;
});

final appCacheServiceProvider = Provider<AppCacheService>(
  (ref) => AppCacheService(ref.watch(documentsDirectoryProvider)),
);

/// The model Chat answers with, or null when nothing is installed yet.
final activeModelProvider = Provider<ModelDescriptor?>(
  (ref) => ref.watch(modelLibraryViewModelProvider).value?.active,
);

/// Drives the `Installed` badge on a catalog card. Per-repository rather than
/// per-file: a different quant of the same weights still counts as having it.
final isRepoInstalledProvider = Provider.family<bool, String>((ref, repoId) {
  final library = ref.watch(modelLibraryViewModelProvider).value;
  return library?.models.any((model) => model.repoId == repoId) ?? false;
});

/// Null once that model has been removed.
final installedModelProvider = Provider.family<ModelDescriptor?, String>(
  (ref, id) => ref.watch(modelLibraryViewModelProvider).value?.byId(id),
);

/// The on-device model. Swap this override to test against a fake.
final llmServiceProvider = Provider<LlmService>((ref) {
  final service = NobodyWhoLlmService();
  ref.onDispose(service.dispose);
  return service;
});

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const AttachmentPicker(),
);

final imageStoreProvider = Provider<ImageStore>(
  (ref) => ImageStore(ref.watch(documentsDirectoryProvider)),
);

/// Built once and held for the app's lifetime; rebuilding a [GoRouter] would
/// throw away the navigation stack.
final routerProvider = Provider<GoRouter>((ref) => createRouter());
