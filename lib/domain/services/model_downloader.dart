import 'dart:async';
import 'dart:developer' as developer;

import 'package:background_downloader/background_downloader.dart';

import '../../data/models/download_progress.dart';
import '../../data/models/gguf_file.dart';
import '../../data/sources/hf_api_client.dart';

class ModelDownloader {
  ModelDownloader({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  static const String _logName = 'ModelDownloader';

  static const String _group = 'models';
  static const BaseDirectory _baseDirectory = BaseDirectory.applicationSupport;

  static const int _retries = 3;

  final FileDownloader _downloader;

  final StreamController<DownloadUpdate> _updates =
      StreamController<DownloadUpdate>.broadcast();

  final Map<String, DownloadProgress> _latest = <String, DownloadProgress>{};

  StreamSubscription<TaskUpdate>? _subscription;
  Future<void>? _ready;
  bool _askedToNotify = false;

  Stream<DownloadUpdate> get updates => _updates.stream;

  Future<void> start({
    required GgufFile file,
    required String displayName,
    String? token,
  }) async {
    await _ensureReady();

    final accepted = await _downloader.enqueue(
      DownloadTask(
        taskId: _taskIdOf(file.id),
        url: file.downloadUrl,
        filename: file.fileName,
        directory: 'models/${_slug(file.repoId)}',
        baseDirectory: _baseDirectory,
        headers: HfApiClient.authHeaders(token),
        group: _group,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: _retries,
        displayName: displayName,
        metaData: file.id,
      ),
    );

    if (!accepted) {
      _emit(
        file.id,
        const DownloadFailed('This download could not be started.'),
      );
    }
  }

  Future<void> pause(String id) async {
    final task = await _taskFor(id);
    if (task is! DownloadTask) return;
    final paused = await _downloader.pause(task);
    if (paused) return;

    developer.log('Could not pause $id', name: _logName);
    final latest = _latest[id];
    if (latest is Downloading) {
      _emit(
        id,
        Downloading(
          fraction: latest.fraction,
          totalBytes: latest.totalBytes,
          canPause: false,
        ),
      );
    }
  }

  Future<void> resume(String id) async {
    final task = await _taskFor(id);
    if (task is! DownloadTask) return;
    if (await _downloader.resume(task)) return;
    _emit(id, const DownloadFailed('This download could not be resumed.'));
  }

  Future<void> cancel(String id) async {
    await _downloader.cancelTaskWithId(_taskIdOf(id));
  }

  Future<Map<String, DownloadProgress>> restore() async {
    await _ensureReady();

    final restored = <String, DownloadProgress>{};
    final finished = <String>[];
    for (final record in await _downloader.database.allRecords(group: _group)) {
      final id = _idOf(record.task);
      if (record.status.isFinalState) {
        finished.add(record.taskId);
        continue;
      }
      final progress = _liveStateOf(record);
      restored[id] = progress;
      _latest[id] = progress;
    }

    await _downloader.database.deleteRecordsWithIds(finished);
    return restored;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _updates.close();
  }

  Future<void> _ensureReady() => _ready ??= _initialise();

  Future<void> _initialise() async {
    _downloader.configureNotification(
      running: const TaskNotification('{filename}', 'Downloading {progress}'),
      complete: const TaskNotification('{filename}', 'Download complete'),
      paused: const TaskNotification('{filename}', 'Paused'),
      error: const TaskNotification('{filename}', 'Download failed'),
      progressBar: true,
    );
    await _downloader.trackTasks();
    _subscription = _downloader.updates.listen(
      _onUpdate,
      onError: (Object error, StackTrace stackTrace) => developer.log(
        'Download update stream failed',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    await _downloader.resumeFromBackground();
  }

  /// Whether reading [status] should be followed by putting the system prompt
  /// up.
  ///
  /// Anything short of granted is asked for. Android reports a permission it
  /// has never asked about as [PermissionStatus.denied], not
  /// [PermissionStatus.undetermined] — that value only ever comes back from
  /// iOS — so testing for undetermined means never asking at all. Asking when
  /// the answer is already a firm no costs nothing: the platform returns it
  /// without drawing a dialog, and Android stops drawing one after two
  /// refusals.
  static bool shouldRequestNotifications(PermissionStatus status) =>
      status != PermissionStatus.granted;

  Future<void> askToNotify() async {
    if (_askedToNotify) return;
    _askedToNotify = true;
    try {
      final permissions = _downloader.permissions;
      final status = await permissions.status(PermissionType.notifications);
      if (!shouldRequestNotifications(status)) return;
      await permissions.request(PermissionType.notifications);
    } catch (error) {
      developer.log('Notification permission', name: _logName, error: error);
    }
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final id = _idOf(update.task);
    switch (update) {
      case TaskProgressUpdate(:final progress, :final task):
        if (progress < 0) return;
        _emit(
          id,
          Downloading(
            fraction: progress,
            totalBytes: update.hasExpectedFileSize
                ? update.expectedFileSize
                : 0,
            canPause: task.allowPause,
          ),
        );
      case TaskStatusUpdate(:final status, :final task, :final exception):
        _emit(id, await _stateOf(status, task, exception));
    }
  }

  Future<DownloadProgress> _stateOf(
    TaskStatus status,
    Task task,
    TaskException? exception,
  ) async {
    final id = _idOf(task);
    return switch (status) {
      TaskStatus.enqueued ||
      TaskStatus.waitingToRetry => const DownloadQueued(),
      TaskStatus.running => _resumedFrom(id, task),
      TaskStatus.paused => _pausedAt(id),
      TaskStatus.complete => DownloadCompleted(await task.filePath()),
      TaskStatus.canceled => const DownloadCancelled(),
      TaskStatus.notFound => const DownloadFailed(
        'That file is no longer on Hugging Face.',
      ),
      TaskStatus.failed => DownloadFailed(_describe(exception)),
    };
  }

  Downloading _resumedFrom(String id, Task task) {
    final latest = _latest[id];
    final (fraction, total) = switch (latest) {
      Downloading(:final fraction, :final totalBytes) => (fraction, totalBytes),
      DownloadPaused(:final fraction, :final totalBytes) => (
        fraction,
        totalBytes,
      ),
      _ => (0.0, 0),
    };
    return Downloading(
      fraction: fraction,
      totalBytes: total,
      canPause: task.allowPause,
    );
  }

  DownloadPaused _pausedAt(String id) {
    final latest = _latest[id];
    if (latest is Downloading) {
      return DownloadPaused(
        fraction: latest.fraction,
        totalBytes: latest.totalBytes,
      );
    }
    return const DownloadPaused(fraction: 0);
  }

  DownloadProgress _liveStateOf(TaskRecord record) {
    final total = record.expectedFileSize >= 0 ? record.expectedFileSize : 0;
    final fraction = record.progress >= 0 ? record.progress : 0.0;
    return switch (record.status) {
      TaskStatus.paused => DownloadPaused(
        fraction: fraction,
        totalBytes: total,
      ),
      TaskStatus.running => Downloading(
        fraction: fraction,
        totalBytes: total,
        canPause: record.task.allowPause,
      ),
      _ => const DownloadQueued(),
    };
  }

  Future<Task?> _taskFor(String id) => _downloader.taskForId(_taskIdOf(id));

  void _emit(String id, DownloadProgress progress) {
    _latest[id] = progress;
    if (_updates.isClosed) return;
    _updates.add((id, progress));
  }

  static String _idOf(Task task) =>
      task.metaData.isEmpty ? task.taskId : task.metaData;

  static String _taskIdOf(String id) => _slug(id);

  static String _slug(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static String _describe(TaskException? exception) {
    final text = exception?.description.trim() ?? '';
    if (text.isEmpty) return 'The download failed.';
    if (text.length <= 120) return text;
    return '${text.substring(0, 117)}…';
  }
}
