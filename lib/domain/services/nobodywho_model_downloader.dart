import 'dart:async';
import 'dart:developer' as developer;

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../data/sources/hf_api_client.dart';
import 'model_downloader.dart';

/// [ModelDownloader] backed by `nobodywho`'s own fetcher.
///
/// `nobodywho.downloadModel` already does everything the Add model sheet needs
/// — progress callbacks throttled to roughly 10 Hz in Rust, an `Authorization`
/// header for gated repositories, and a cache that `getCachedModels()` can
/// report back — so the app does not stream bytes itself.
///
/// The one thing it does not offer is **cancellation**: once started, a
/// download runs to completion or fails, and killing the app loses the bytes
/// rather than pausing them. That is why [ModelDownloader] is an interface —
/// swapping in a `package:http` downloader with HTTP Range resume is a
/// one-class change if that becomes worth doing.
class NobodyWhoModelDownloader implements ModelDownloader {
  const NobodyWhoModelDownloader();

  static const String _logName = 'NobodyWhoModelDownloader';

  @override
  Stream<DownloadProgress> download({required String url, String? token}) {
    final controller = StreamController<DownloadProgress>();
    unawaited(_run(controller, url, token));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<DownloadProgress> controller,
    String url,
    String? token,
  ) async {
    controller.add(const Downloading(received: 0, total: 0));
    try {
      final path = await nobodywho.downloadModel(
        modelPath: url,
        headers: HfApiClient.authHeaders(token),
        onDownloadProgress: (downloaded, total) {
          if (controller.isClosed) return;
          controller.add(
            Downloading(received: downloaded.toInt(), total: total.toInt()),
          );
        },
      );
      controller.add(DownloadCompleted(path));
    } catch (error, stackTrace) {
      developer.log(
        'Download failed for $url',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
      controller.add(DownloadFailed(_describe(error)));
    } finally {
      await controller.close();
    }
  }

  /// Native errors arrive as long, unreadable strings; this keeps the card
  /// readable while the full text goes to the log.
  static String _describe(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return 'The download failed.';
    if (text.length <= 120) return text;
    return '${text.substring(0, 117)}…';
  }
}

/// Every `.gguf` in `nobodywho`'s cache, as `(absolute path, size in bytes)`.
///
/// Wrapped in a function so the only `nobodywho` import stays in this layer.
List<(String, int)> cachedModelFiles() => <(String, int)>[
  for (final (path, size) in nobodywho.getCachedModels()) (path, size.toInt()),
];
