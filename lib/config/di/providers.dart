import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/api_keys.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/api_key_repository.dart';
import '../../data/repositories/app_settings_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/hugging_face_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/model_library_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/hf_api_client.dart';
import '../../data/sources/json_file_store.dart';
import '../../data/sources/secure_key_store.dart';
import '../../domain/services/app_cache_service.dart';
import '../../domain/services/attachment_picker.dart';
import '../../domain/services/image_store.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/model_downloader.dart';
import '../../domain/services/nobodywho_llm_service.dart';
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
