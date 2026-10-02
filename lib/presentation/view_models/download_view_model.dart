import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

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
  static const String _logName = 'DownloadViewModel';

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
      if (progress is! DownloadCompleted) {
        _put(file.id, progress);
        continue;
      }
      await _install(repo, file, progress.localPath);
    }
  }

  /// Records a finished download, unless the bytes that landed are short.
  ///
  /// The downloader can neither resume nor cancel, so a transfer interrupted by
  /// a dropped connection still ends as [DownloadCompleted] — leaving a partial
  /// `.gguf` that only fails much later, inside the native loader, as an
  /// unreadable error on the chat screen. Checking here is what turns that into
  /// a retryable message on the card the user just tapped.
  Future<void> _install(
    HfRepoSummary repo,
    GgufFile file,
    String localPath,
  ) async {
    final length = await File(localPath).length();
    if (length < file.sizeBytes) {
      developer.log(
        'Discarding ${file.id}: $length of ${file.sizeBytes} bytes arrived',
        name: _logName,
      );
      await _discard(localPath);
      _put(file.id, const DownloadFailed('The download was cut short.'));
      return;
    }

    _put(file.id, DownloadCompleted(localPath));
    await ref
        .read(modelLibraryViewModelProvider.notifier)
        .install(
          ModelDescriptor.installed(
            repo: repo,
            file: file,
            localPath: localPath,
          ),
        );
  }

  /// Removes a partial file so the next attempt starts clean rather than
  /// finding a cached model of the right name and the wrong length.
  Future<void> _discard(String localPath) async {
    try {
      await File(localPath).delete();
    } on FileSystemException catch (error) {
      developer.log(
        'Could not delete $localPath',
        name: _logName,
        error: error,
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
