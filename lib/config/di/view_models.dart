import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/chat_session.dart';
import '../../data/models/download_progress.dart';
import '../../data/models/gguf_file.dart';
import '../../data/models/hf_repo_summary.dart';
import '../../data/models/home_stats.dart';
import '../../data/models/sampler_settings.dart';
import '../../data/repositories/model_library_repository.dart';
import '../../data/sources/hf_api_client.dart';
import '../../domain/services/home_stats_builder.dart';
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

final modelLibraryViewModelProvider =
    AsyncNotifierProvider<ModelLibraryViewModel, ModelLibrary>(
      ModelLibraryViewModel.new,
    );

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

final repoFilesProvider = FutureProvider.family<List<GgufFile>, String>(
  (ref, repoId) => ref.watch(huggingFaceRepositoryProvider).filesOf(repoId),
  retry: _noNetworkRetry,
);

final repoStatsProvider = FutureProvider.family<HfRepoSummary, String>(
  (ref, repoId) => ref.watch(huggingFaceRepositoryProvider).detailsOf(repoId),
  retry: _noNetworkRetry,
);

Duration? _noNetworkRetry(int retryCount, Object error) =>
    error is HfApiException ? null : const Duration(seconds: 1);

final filteredSessionsProvider = Provider<List<ChatSession>>((ref) {
  final sessions =
      ref.watch(sessionsViewModelProvider).value ?? const <ChatSession>[];
  final filter = ref.watch(sessionFilterProvider);
  if (!filter.isActive) return sessions;

  final now = DateTime.now();
  return sessions.where((session) => filter.matches(session, now)).toList();
});

final homeStatsProvider = Provider<HomeStats>(
  (ref) => buildHomeStats(
    sessions:
        ref.watch(sessionsViewModelProvider).value ?? const <ChatSession>[],
    library:
        ref.watch(modelLibraryViewModelProvider).value ?? ModelLibrary.empty,
    now: DateTime.now(),
  ),
);
