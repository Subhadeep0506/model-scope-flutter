import '../../data/models/byte_size.dart';
import '../../data/models/gguf_file.dart';

/// How far a download has got.
///
/// A download is owned by the operating system rather than by the screen that
/// started it, so these states have to describe a transfer the app may not have
/// been running for — hence [DownloadPaused] and [DownloadQueued], which the
/// previous fire-and-forget downloader had no way to represent.
sealed class DownloadProgress {
  const DownloadProgress();
}

/// Accepted by the system, waiting its turn or waiting for a network.
final class DownloadQueued extends DownloadProgress {
  const DownloadQueued();
}

/// Bytes are arriving.
final class Downloading extends DownloadProgress {
  const Downloading({
    required this.fraction,
    this.totalBytes = 0,
    this.canPause = false,
  });

  /// `0.0`–`1.0`. Always known, unlike the byte counts.
  final double fraction;

  /// `0` when the server never reported a content length.
  final int totalBytes;

  /// Whether this transfer can be suspended and picked up again.
  ///
  /// Resuming needs the server to honour an HTTP range request. Hugging Face's
  /// CDN does, but a redirect could land somewhere that does not, and offering
  /// a pause button that silently restarts the download would be worse than
  /// offering none.
  final bool canPause;

  /// `51`, for the `downloading 51%` caption.
  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();

  int get receivedBytes =>
      totalBytes <= 0 ? 0 : (fraction.clamp(0.0, 1.0) * totalBytes).round();
}

/// Suspended with its bytes kept on disk, ready to carry on.
final class DownloadPaused extends DownloadProgress {
  const DownloadPaused({required this.fraction, this.totalBytes = 0});

  final double fraction;
  final int totalBytes;

  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();

  /// `paused at 51% · 1.10 GB of 2.15 GB`, so a half-finished download says
  /// what it would cost to finish.
  String get caption {
    if (totalBytes <= 0) return 'paused at $percent%';
    final received = (fraction.clamp(0.0, 1.0) * totalBytes).round();
    return 'paused · ${formatBytes(received)} of ${formatBytes(totalBytes)}';
  }
}

final class DownloadCompleted extends DownloadProgress {
  const DownloadCompleted(this.localPath);

  /// Absolute path to the weights, ready to hand to the model loader.
  final String localPath;
}

final class DownloadFailed extends DownloadProgress {
  const DownloadFailed(this.message);

  final String message;
}

/// The user cancelled. Distinct from [DownloadFailed] so the row can simply
/// disappear instead of accusing the app of breaking.
final class DownloadCancelled extends DownloadProgress {
  const DownloadCancelled();
}

/// A progress report, tagged with the [GgufFile.id] it belongs to.
typedef DownloadUpdate = (String id, DownloadProgress progress);

/// Fetches GGUF weights onto the device.
///
/// An interface so the view models can be tested against a fake, the same way
/// `LlmService` keeps `package:nobodywho` out of everything above it.
///
/// Unlike the previous version this is not a per-call stream. A transfer
/// outlives the widget that started it, the view model that watched it, and
/// often the app process itself, so progress arrives on one long-lived
/// [updates] stream keyed by file id instead.
abstract interface class ModelDownloader {
  /// Every progress report, for every transfer, for as long as the app runs.
  Stream<DownloadUpdate> get updates;

  /// Reattaches to transfers the system kept running while the app was gone.
  ///
  /// Returns only live states — queued, downloading, paused. A transfer that
  /// finished or failed in a previous run is not resurrected; the first is
  /// already recorded in the library, and the second would surface an error
  /// about something the user has long forgotten.
  Future<Map<String, DownloadProgress>> restore();

  /// Begins fetching [file]. [displayName] names it in the system notification.
  Future<void> start({
    required GgufFile file,
    required String displayName,
    String? token,
  });

  Future<void> pause(String id);
  Future<void> resume(String id);

  /// Stops the transfer and discards its partial bytes.
  Future<void> cancel(String id);

  Future<void> dispose();
}
