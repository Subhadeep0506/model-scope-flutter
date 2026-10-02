import 'dart:async';
import 'dart:developer' as developer;

import 'package:background_downloader/background_downloader.dart';

import '../../data/models/gguf_file.dart';
import '../../data/sources/hf_api_client.dart';
import 'model_downloader.dart';

/// [ModelDownloader] backed by `background_downloader`.
///
/// The previous implementation handed the job to `nobodywho`, which fetched the
/// file on the app's own isolate with no way to pause, resume or cancel it. On a
/// phone that meant a multi-gigabyte transfer stalled the moment Android froze
/// the process — screen off, app backgrounded — and any interruption threw away
/// every byte.
///
/// This hands the transfer to the platform instead: Android runs it in a
/// foreground service through WorkManager, iOS in a background `URLSession`.
/// The download keeps going with the screen off, survives the app being swiped
/// away, and resumes from its partial file rather than from zero.
class BackgroundModelDownloader implements ModelDownloader {
  BackgroundModelDownloader({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  static const String _logName = 'BackgroundModelDownloader';

  /// Groups this app's transfers so [restore] never trips over a task some
  /// other part of the app enqueued.
  static const String _group = 'models';

  /// Weights land under the app's support directory rather than `nobodywho`'s
  /// cache. The loader takes any absolute path, and an installed model records
  /// the path it was written to, so earlier downloads keep working untouched.
  static const BaseDirectory _baseDirectory = BaseDirectory.applicationSupport;

  /// A dropped connection mid-download is routine on a phone; retrying before
  /// reporting failure saves the user a trip back to the sheet.
  static const int _retries = 3;

  final FileDownloader _downloader;

  final StreamController<DownloadUpdate> _updates =
      StreamController<DownloadUpdate>.broadcast();

  /// The last state seen per file id.
  ///
  /// A status change carries no byte counts, so pausing at 51% would otherwise
  /// redraw the bar at zero. This is what lets the paused state keep the
  /// percentage the progress updates established.
  final Map<String, DownloadProgress> _latest = <String, DownloadProgress>{};

  StreamSubscription<TaskUpdate>? _subscription;
  Future<void>? _ready;

  /// Once per run. The system only shows the dialog once anyway, and asking
  /// again on every download would be a permission check per tap.
  bool _askedToNotify = false;

  @override
  Stream<DownloadUpdate> get updates => _updates.stream;

  @override
  Future<void> start({
    required GgufFile file,
    required String displayName,
    String? token,
  }) async {
    await _ensureReady();
    await _askToNotify();

    final accepted = await _downloader.enqueue(
      DownloadTask(
        taskId: _taskIdOf(file.id),
        url: file.downloadUrl,
        filename: file.fileName,
        // One directory per repository: two repositories can publish files of
        // exactly the same name, and they must not overwrite each other.
        directory: 'models/${_slug(file.repoId)}',
        baseDirectory: _baseDirectory,
        headers: HfApiClient.authHeaders(token),
        group: _group,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: _retries,
        displayName: displayName,
        // The app's own id for this file, carried on the task so a transfer
        // reattached after a restart can still be matched to its row.
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

  @override
  Future<void> pause(String id) async {
    final task = await _taskFor(id);
    if (task is! DownloadTask) return;
    final paused = await _downloader.pause(task);
    if (paused) return;

    // Pause is best-effort: the platform refuses when the server will not
    // honour a range request. Saying so beats a button that does nothing.
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

  @override
  Future<void> resume(String id) async {
    final task = await _taskFor(id);
    if (task is! DownloadTask) return;
    if (await _downloader.resume(task)) return;
    _emit(id, const DownloadFailed('This download could not be resumed.'));
  }

  @override
  Future<void> cancel(String id) async {
    await _downloader.cancelTaskWithId(_taskIdOf(id));
  }

  @override
  Future<Map<String, DownloadProgress>> restore() async {
    await _ensureReady();

    final restored = <String, DownloadProgress>{};
    final finished = <String>[];
    for (final record in await _downloader.database.allRecords(group: _group)) {
      final id = _idOf(record.task);
      if (record.status.isFinalState) {
        // Nothing to show, and keeping it would grow the database forever.
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

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _updates.close();
  }

  /// Subscribes to the platform's updates and reclaims anything it kept running.
  ///
  /// Deferred rather than done in the constructor so the provider stays cheap to
  /// create, and memoised on a future so two simultaneous taps cannot subscribe
  /// twice.
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

  /// Asks for the notification permission the first time the user downloads
  /// something, which is the only moment the request makes sense.
  ///
  /// Asking at launch would be a prompt with no context, and the answer does
  /// not gate anything: a denied permission costs the progress notification,
  /// not the download. Failures here are logged and ignored for the same
  /// reason — never let a permission dialog stop a transfer.
  Future<void> _askToNotify() async {
    if (_askedToNotify) return;
    _askedToNotify = true;
    try {
      final permissions = _downloader.permissions;
      if (await permissions.status(PermissionType.notifications) ==
          PermissionStatus.undetermined) {
        await permissions.request(PermissionType.notifications);
      }
    } catch (error) {
      developer.log('Notification permission', name: _logName, error: error);
    }
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final id = _idOf(update.task);
    switch (update) {
      case TaskProgressUpdate(:final progress, :final task):
        // Negative values are status sentinels, not fractions; the matching
        // TaskStatusUpdate reports those properly.
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

  /// Keeps the bar where it was when a transfer starts or restarts, rather than
  /// snapping to zero until the first progress update lands.
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

  /// The live states a reattached record can be in, mapped the same way
  /// [_stateOf] maps them — minus the final ones, which [restore] drops.
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

  /// The app's id for a transfer, which is a [GgufFile.id].
  ///
  /// Read from the task's metadata rather than its id because a task id has to
  /// survive being used as a database key, and a file id contains slashes.
  static String _idOf(Task task) =>
      task.metaData.isEmpty ? task.taskId : task.metaData;

  static String _taskIdOf(String id) => _slug(id);

  /// Strips a repository or file id down to something safe as a path segment
  /// and a database key, while staying recognisable in a file listing.
  static String _slug(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Platform errors arrive as long, unreadable strings; this keeps the row
  /// readable while the full text goes to the log.
  static String _describe(TaskException? exception) {
    final text = exception?.description.trim() ?? '';
    if (text.isEmpty) return 'The download failed.';
    if (text.length <= 120) return text;
    return '${text.substring(0, 117)}…';
  }
}
