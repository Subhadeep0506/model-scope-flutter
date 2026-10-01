import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/api_keys.dart';
import '../../data/models/gguf_file.dart';
import '../../data/models/hf_repo_summary.dart';
import '../../data/models/model_descriptor.dart';
import '../../domain/services/model_downloader.dart';

/// Tracks every download in flight, keyed by [GgufFile.id].
///
/// Lives above the browse sheet on purpose: dismissing the sheet must not
/// abandon a download, and the progress bar has to come back in the same state
/// when the sheet is reopened.
class DownloadViewModel extends Notifier<Map<String, DownloadProgress>> {
  @override
  Map<String, DownloadProgress> build() => const <String, DownloadProgress>{};

  DownloadProgress? progressOf(String id) => state[id];

  bool get hasActiveDownload =>
      state.values.any((progress) => progress is Downloading);

  /// Fetches [file] and records it in the library once the bytes land.
  ///
  /// Does nothing when the same file is already downloading, so a double tap
  /// on a quant chip cannot start two transfers.
  Future<void> start({
    required HfRepoSummary repo,
    required GgufFile file,
  }) async {
    if (state[file.id] is Downloading) return;

    final token = await ref
        .read(apiKeyRepositoryProvider)
        .read(ApiKeyKind.huggingFace);

    final stream = ref
        .read(modelDownloaderProvider)
        .download(url: file.downloadUrl, token: token);

    await for (final progress in stream) {
      _put(file.id, progress);
      if (progress is! DownloadCompleted) continue;

      await ref
          .read(modelLibraryViewModelProvider.notifier)
          .install(
            ModelDescriptor.installed(
              repo: repo,
              file: file,
              localPath: progress.localPath,
            ),
          );
    }
  }

  /// Clears a finished or failed entry, so the card returns to its idle chips.
  void dismiss(String id) {
    if (!state.containsKey(id)) return;
    state = <String, DownloadProgress>{...state}..remove(id);
  }

  void _put(String id, DownloadProgress progress) =>
      state = <String, DownloadProgress>{...state, id: progress};
}
