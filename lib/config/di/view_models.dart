import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/gguf_file.dart';
import '../../data/models/hf_repo_summary.dart';
import '../../data/models/sampler_settings.dart';
import '../../data/repositories/model_library_repository.dart';
import '../../data/sources/hf_api_client.dart';
import '../../domain/services/model_downloader.dart';
import '../../presentation/view_models/api_keys_state.dart';
import '../../presentation/view_models/api_keys_view_model.dart';
import '../../presentation/view_models/app_settings_view_model.dart';
import '../../presentation/view_models/catalog_state.dart';
import '../../presentation/view_models/catalog_view_model.dart';
import '../../presentation/view_models/chat_state.dart';
import '../../presentation/view_models/chat_view_model.dart';
import '../../presentation/view_models/download_view_model.dart';
import '../../presentation/view_models/model_library_view_model.dart';
import '../../presentation/view_models/sampler_view_model.dart';
import '../../presentation/view_models/session_filter_view_model.dart';
import '../../presentation/view_models/sessions_view_model.dart';
import '../../presentation/view_models/storage_view_model.dart';
import 'providers.dart';

final sessionsViewModelProvider =
    AsyncNotifierProvider<SessionsViewModel, List<ChatSession>>(
      SessionsViewModel.new,
    );

final samplerViewModelProvider =
    AsyncNotifierProvider<SamplerViewModel, SamplerSettings>(
      SamplerViewModel.new,
    );

final chatViewModelProvider = NotifierProvider<ChatViewModel, ChatState>(
  ChatViewModel.new,
);

final sessionFilterProvider =
    NotifierProvider<SessionFilterViewModel, SessionFilter>(
      SessionFilterViewModel.new,
    );

/// The installed models and which one Chat answers with.
final modelLibraryViewModelProvider =
    AsyncNotifierProvider<ModelLibraryViewModel, ModelLibrary>(
      ModelLibraryViewModel.new,
    );

/// The Model catalog screen's list, read from the shipped manifest.
final catalogViewModelProvider =
    AsyncNotifierProvider<CatalogViewModel, CatalogState>(CatalogViewModel.new);

final downloadViewModelProvider =
    NotifierProvider<DownloadViewModel, Map<String, DownloadProgress>>(
      DownloadViewModel.new,
    );

final appSettingsViewModelProvider =
    AsyncNotifierProvider<AppSettingsViewModel, AppSettings>(
      AppSettingsViewModel.new,
    );

final apiKeysViewModelProvider =
    AsyncNotifierProvider<ApiKeysViewModel, ApiKeysState>(ApiKeysViewModel.new);

final storageViewModelProvider = AsyncNotifierProvider<StorageViewModel, int>(
  StorageViewModel.new,
);

/// The GGUF files of one repo, fetched when its model sheet is opened.
///
/// A plain [FutureProvider.family] rather than a notifier: there is no state to
/// mutate, and Riverpod's per-argument caching means reopening a sheet does not
/// refetch. Retry is `ref.invalidate(repoFilesProvider(repoId))`.
///
/// Nothing in the catalog list watches this. That is deliberate and is the
/// single biggest reduction in traffic from the previous build, where every
/// card on screen fired a tree request of its own just to label its chips.
final repoFilesProvider = FutureProvider.family<List<GgufFile>, String>(
  (ref, repoId) => ref.watch(huggingFaceRepositoryProvider).filesOf(repoId),
  retry: _noNetworkRetry,
);

/// Live downloads, likes and file count for one catalog card.
///
/// One request per manifest entry per app run, and nothing depends on it: the
/// card renders in full from the manifest and simply omits its stats row when
/// this is still loading or has failed.
final repoStatsProvider = FutureProvider.family<HfRepoSummary, String>(
  (ref, repoId) => ref.watch(huggingFaceRepositoryProvider).detailsOf(repoId),
  retry: _noNetworkRetry,
);

/// Leaves a failed Hugging Face call failed, instead of re-requesting it.
///
/// Riverpod retries a provider whose build threw, on a backoff timer, and keeps
/// the state in `AsyncLoading` while it does. For these two that is the wrong
/// behaviour twice over: a rate-limited or rejected request is not going to
/// succeed on its own, and re-sending it is what drew the 429 in the first
/// place — meanwhile the card or the sheet sits on a spinner rather than saying
/// what went wrong. Both already offer an explicit Retry, which is the user's
/// call to make.
Duration? _noNetworkRetry(int retryCount, Object error) =>
    error is HfApiException ? null : const Duration(seconds: 1);

/// The Chats list after the search field and both dropdowns are applied.
///
/// Derived here so the screen stays a pure observer of one value.
final filteredSessionsProvider = Provider<List<ChatSession>>((ref) {
  final sessions =
      ref.watch(sessionsViewModelProvider).value ?? const <ChatSession>[];
  final filter = ref.watch(sessionFilterProvider);
  if (!filter.isActive) return sessions;

  final now = DateTime.now();
  return sessions.where((session) => filter.matches(session, now)).toList();
});
