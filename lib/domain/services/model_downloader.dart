/// How far a download has got.
sealed class DownloadProgress {
  const DownloadProgress();
}

/// Bytes are arriving. [total] is 0 until the server reports a content length.
class Downloading extends DownloadProgress {
  const Downloading({required this.received, required this.total});

  final int received;
  final int total;

  /// `0.0`–`1.0`, or null while the total is unknown — which is the difference
  /// between a determinate bar and a spinner.
  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  /// `51`, for the `downloading 51%` caption.
  int get percent => ((fraction ?? 0) * 100).round();
}

class DownloadCompleted extends DownloadProgress {
  const DownloadCompleted(this.localPath);

  /// Absolute path to the weights, ready to hand to the model loader.
  final String localPath;
}

class DownloadFailed extends DownloadProgress {
  const DownloadFailed(this.message);

  final String message;
}

/// Fetches GGUF weights onto the device.
///
/// An interface so the view models can be tested against a fake, the same way
/// `LlmService` keeps `package:nobodywho` out of everything above it.
abstract interface class ModelDownloader {
  /// Streams progress until the file is on disk or the attempt fails.
  ///
  /// There is deliberately no cancel: the underlying implementation offers
  /// none. See [NobodyWhoModelDownloader].
  Stream<DownloadProgress> download({required String url, String? token});
}
