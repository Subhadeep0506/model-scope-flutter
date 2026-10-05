import 'byte_size.dart';
import 'gguf_file.dart';

/// How far a download has got. The system owns the transfer, not the screen
/// that started it, so these states have to describe one the app may not have
/// been running for — hence [DownloadQueued] and [DownloadPaused].
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

  /// Resuming needs the server to honour an HTTP range request. Hugging Face's
  /// CDN does, but a redirect may not, and a pause button that silently
  /// restarts the download is worse than no pause button.
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
