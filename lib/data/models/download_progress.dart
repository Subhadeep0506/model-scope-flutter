import 'byte_size.dart';

sealed class DownloadProgress {
  const DownloadProgress();
}

final class DownloadQueued extends DownloadProgress {
  const DownloadQueued();
}

final class Downloading extends DownloadProgress {
  const Downloading({
    required this.fraction,
    this.totalBytes = 0,
    this.canPause = false,
  });
  final double fraction;
  final int totalBytes;
  final bool canPause;
  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();

  int get receivedBytes =>
      totalBytes <= 0 ? 0 : (fraction.clamp(0.0, 1.0) * totalBytes).round();
}

final class DownloadPaused extends DownloadProgress {
  const DownloadPaused({required this.fraction, this.totalBytes = 0});

  final double fraction;
  final int totalBytes;

  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();

  String get caption {
    if (totalBytes <= 0) return 'paused at $percent%';
    final received = (fraction.clamp(0.0, 1.0) * totalBytes).round();
    return 'paused · ${formatBytes(received)} of ${formatBytes(totalBytes)}';
  }
}

final class DownloadCompleted extends DownloadProgress {
  const DownloadCompleted(this.localPath);
  final String localPath;
}

final class DownloadFailed extends DownloadProgress {
  const DownloadFailed(this.message);
  final String message;
}

final class DownloadCancelled extends DownloadProgress {
  const DownloadCancelled();
}

typedef DownloadUpdate = (String id, DownloadProgress progress);
