import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/api_keys.dart';
import '../../data/models/catalog_model.dart';
import '../../data/models/gguf_file.dart';
import '../../data/models/model_descriptor.dart';
import '../../domain/services/model_downloader.dart';

/// Tracks every download, keyed by [GgufFile.id].
///
/// Lives above the catalog screen on purpose: the transfer belongs to the
/// operating system now, so leaving the screen — or the app — must not abandon
/// it, and the row has to come back in the right state when the user returns.
class DownloadViewModel extends Notifier<Map<String, DownloadProgress>> {
  static const String _logName = 'DownloadViewModel';

  /// The repository a download belongs to, so a finished transfer can be
  /// recorded with the title and parameter count the catalog gave it.
  final Map<String, CatalogModel> _sources = <String, CatalogModel>{};

  @override
  Map<String, DownloadProgress> build() {
    final downloader = ref.watch(modelDownloaderProvider);
    final subscription = downloader.updates.listen(_onUpdate);
    ref.onDispose(subscription.cancel);
    unawaited(_restore());
    return const <String, DownloadProgress>{};
  }

  DownloadProgress? progressOf(String id) => state[id];

  bool get hasActiveDownload =>
      state.values.any((progress) => progress is Downloading);

  /// Fetches [file] and records it in the library once the bytes land.
  ///
  /// Does nothing when the same file is already in flight, so a double tap on a
  /// download button cannot start two transfers.
  Future<void> start({
    required CatalogModel model,
    required GgufFile file,
  }) async {
    if (_isLive(state[file.id])) return;
    _sources[file.id] = model;

    final token = await ref
        .read(apiKeyRepositoryProvider)
        .read(ApiKeyKind.huggingFace);

    _put(file.id, const DownloadQueued());
    await ref
        .read(modelDownloaderProvider)
        .start(file: file, displayName: model.name, token: token);
  }

  Future<void> pause(String id) => ref.read(modelDownloaderProvider).pause(id);

  Future<void> resume(String id) =>
      ref.read(modelDownloaderProvider).resume(id);

  Future<void> cancel(String id) =>
      ref.read(modelDownloaderProvider).cancel(id);

  /// Clears a finished or failed entry, so the row returns to its idle button.
  void dismiss(String id) {
    if (!state.containsKey(id)) return;
    state = <String, DownloadProgress>{...state}..remove(id);
  }

  /// Picks up transfers the system carried on with while the app was closed.
  Future<void> _restore() async {
    try {
      final live = await ref.read(modelDownloaderProvider).restore();
      if (live.isEmpty) return;
      state = <String, DownloadProgress>{...live, ...state};
    } catch (error, stackTrace) {
      developer.log(
        'Could not restore downloads',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onUpdate(DownloadUpdate update) {
    final (id, progress) = update;
    switch (progress) {
      case DownloadCompleted(:final localPath):
        unawaited(_install(id, localPath));
      case DownloadCancelled():
        dismiss(id);
      case _:
        _put(id, progress);
    }
  }

  /// Records a finished download, unless the bytes that landed are short.
  ///
  /// The platform verifies the content length itself, so this should never
  /// fire — but a partial `.gguf` only fails much later, inside the native
  /// loader, as an unreadable error on the chat screen. Checking here is what
  /// turns that into a retryable message on the row the user just tapped.
  Future<void> _install(String id, String localPath) async {
    final model = _sources[id];
    final file = await _fileFor(id, model);
    if (model == null || file == null) {
      // Restored from a previous run, so the catalog entry was never seen this
      // session. The bytes are on disk; the library picks them up next launch.
      _put(id, DownloadCompleted(localPath));
      return;
    }

    final length = await _lengthOf(localPath);
    if (length < file.sizeBytes) {
      developer.log(
        'Discarding $id: $length of ${file.sizeBytes} bytes arrived',
        name: _logName,
      );
      await _discard(localPath);
      _put(id, const DownloadFailed('The download was cut short.'));
      return;
    }

    _put(id, DownloadCompleted(localPath));
    await ref
        .read(modelLibraryViewModelProvider.notifier)
        .install(
          ModelDescriptor.installed(
            model: model,
            file: file,
            localPath: localPath,
          ),
        );
  }

  /// The catalog's record of the file that just finished, for its expected size.
  Future<GgufFile?> _fileFor(String id, CatalogModel? model) async {
    if (model == null) return null;
    try {
      final files = await ref.read(repoFilesProvider(model.repoId).future);
      for (final file in files) {
        if (file.id == id) return file;
      }
    } catch (error) {
      developer.log('Could not resolve $id', name: _logName, error: error);
    }
    return null;
  }

  Future<int> _lengthOf(String localPath) async {
    try {
      return await File(localPath).length();
    } on FileSystemException {
      return 0;
    }
  }

  /// Removes a partial file so the next attempt starts clean rather than
  /// finding a model of the right name and the wrong length.
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

  /// Whether this file is already queued, downloading or paused — all states a
  /// second tap must not restart.
  static bool _isLive(DownloadProgress? progress) => switch (progress) {
    DownloadQueued() || Downloading() || DownloadPaused() => true,
    _ => false,
  };

  void _put(String id, DownloadProgress progress) =>
      state = <String, DownloadProgress>{...state, id: progress};
}
