import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/api_keys.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/repositories/api_key_repository.dart';
import '../../data/repositories/app_settings_repository.dart';
import '../../data/repositories/hugging_face_repository.dart';
import '../../data/repositories/local_model_library_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_settings_repository.dart';
import '../../data/repositories/model_library_repository.dart';
import '../../data/repositories/prefs_session_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/hf_api_client.dart';
import '../../data/sources/json_file_store.dart';
import '../../data/sources/secure_key_store.dart';
import '../../domain/services/app_cache_service.dart';
import '../../domain/services/attachment_picker.dart';
import '../../domain/services/llm_service.dart';
import '../../domain/services/model_downloader.dart';
import '../../domain/services/nobodywho_llm_service.dart';
import '../../domain/services/nobodywho_model_downloader.dart';
import '../router/app_router.dart';
import 'view_models.dart';

/// The app's writable directory.
///
/// Resolved in `main()` and injected with a `ProviderScope` override so the
/// stores below can stay synchronous. Tests override it with a temp directory.
final documentsDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'documentsDirectoryProvider must be overridden in ProviderScope.',
  ),
);

/// Shared preferences, read and written on demand.
///
/// Unlike [documentsDirectoryProvider] this needs no override in `main()` —
/// [SharedPreferencesAsync] has no instance to prime. Tests swap the platform
/// implementation instead.
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

/// Sessions live in shared preferences, with the old `sessions.json` store
/// passed in as the one-shot migration source for upgrades from the build that
/// wrote it. The file is read, never deleted, so a bad import is recoverable.
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => PrefsSessionRepository(
    ref.watch(sharedPreferencesProvider),
    LocalSessionRepository(ref.watch(sessionStoreProvider)),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(settingsStoreProvider)),
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => LocalAppSettingsRepository(ref.watch(settingsStoreProvider)),
);

final modelLibraryRepositoryProvider = Provider<ModelLibraryRepository>(
  (ref) => LocalModelLibraryRepository(ref.watch(modelStoreProvider)),
);

/// Closed with the provider, so a disposed scope does not leak a socket pool.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const PlatformSecureKeyStore(),
);

final apiKeyRepositoryProvider = Provider<ApiKeyRepository>(
  (ref) => SecureApiKeyRepository(ref.watch(secureKeyStoreProvider)),
);

final hfApiClientProvider = Provider<HfApiClient>(
  (ref) => HfApiClient(ref.watch(httpClientProvider)),
);

/// The Hugging Face catalog.
///
/// The token is read per request rather than captured, so pasting one into the
/// API keys card takes effect on the next call without rebuilding anything.
final huggingFaceRepositoryProvider = Provider<HuggingFaceRepository>(
  (ref) => HfHuggingFaceRepository(
    ref.watch(hfApiClientProvider),
    () => ref.read(apiKeyRepositoryProvider).read(ApiKeyKind.huggingFace),
  ),
);

final modelDownloaderProvider = Provider<ModelDownloader>(
  (ref) => const NobodyWhoModelDownloader(),
);

final appCacheServiceProvider = Provider<AppCacheService>(
  (ref) => AppCacheService(ref.watch(documentsDirectoryProvider)),
);

/// The model Chat answers with, or null when nothing is installed yet.
///
/// Derived from the library rather than hardcoded: models now arrive through
/// the Settings screen, and the active one is whichever the user last picked.
final activeModelProvider = Provider<ModelDescriptor?>(
  (ref) => ref.watch(modelLibraryViewModelProvider).value?.active,
);

/// Looks up an installed model by id, for rows that name the model a session
/// was recorded against. Returns null once that model has been removed.
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
  (ref) => const FilePickerAttachmentPicker(),
);

/// Built once and held for the app's lifetime; rebuilding a [GoRouter] would
/// throw away the navigation stack.
final routerProvider = Provider<GoRouter>((ref) => createRouter());
