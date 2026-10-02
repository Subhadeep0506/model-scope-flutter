import 'dart:async';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/hf_repo_summary.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/domain/services/model_downloader.dart';
import 'package:model_scope_flutter/presentation/view_models/download_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeModelDownloader downloader;
  late FakeModelLibraryRepository library;
  late FakeApiKeyRepository keys;
  late ProviderContainer container;
  late Directory directory;
  late String downloadedPath;

  /// Stands in for the finished file. Small, but real: the view model stats
  /// what landed before it records it, so a fictional path would take the
  /// could-not-measure branch instead of the one under test.
  const int sizeBytes = 2048;

  final HfRepoSummary repo = fakeRepo();
  final GgufFile file = fakeGgufFile(sizeBytes: sizeBytes);

  /// Replaces the downloaded file with one of [bytes], standing in for a
  /// transfer that was cut off part-way.
  Future<void> writeWeights(int bytes) =>
      File(downloadedPath).writeAsBytes(List<int>.filled(bytes, 0));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_scope_download');
    downloadedPath = '${directory.path}${Platform.pathSeparator}model.gguf';
    await writeWeights(sizeBytes);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ProviderContainer containerWith({
    List<DownloadProgress>? script,
    StreamController<DownloadProgress>? controller,
    Map<ApiKeyKind, String>? storedKeys,
  }) {
    downloader = FakeModelDownloader(
      script:
          script ??
          <DownloadProgress>[
            const Downloading(received: 50, total: 100),
            DownloadCompleted(downloadedPath),
          ],
    )..controller = controller;
    library = FakeModelLibraryRepository();
    keys = FakeApiKeyRepository(storedKeys);
    return ProviderContainer.test(
      retry: noRetry,
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(),
        downloader: downloader,
        library: library,
        apiKeys: keys,
      ),
    );
  }

  DownloadViewModel notifier() =>
      container.read(downloadViewModelProvider.notifier);

  Future<ModelLibrary> libraryState() =>
      container.read(modelLibraryViewModelProvider.future);

  test('a completed download is recorded in the library', () async {
    // Arrange
    container = containerWith();

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert — the path is the downloader's, not a guess at where it put it.
    final installed = (await libraryState()).models.single;
    check(installed.id).equals(file.id);
    check(installed.localPath).equals(downloadedPath);
    check(installed.quantization).equals('Q8_0');
    check(installed.sizeBytes).equals(file.sizeBytes);
    check(installed.name).equals('SmolLM2 360M Instruct');
  });

  test('the first download becomes the active model', () async {
    // Arrange — nothing installed, so Chat has nothing to answer with.
    container = containerWith();

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert — one tap, not two, to get from empty to usable.
    check((await libraryState()).activeId).equals(file.id);
  });

  test('a later download does not steal the active model', () async {
    // Arrange
    container = containerWith();
    await notifier().start(repo: repo, file: file);
    final second = fakeGgufFile(
      fileName: 'smollm2-360m-instruct-q4_k_m.gguf',
      sizeBytes: sizeBytes,
    );

    // Act
    await notifier().start(repo: repo, file: second);

    // Assert
    check((await libraryState()).models).length.equals(2);
    check((await libraryState()).activeId).equals(file.id);
  });

  test('the Hugging Face token is passed to the downloader', () async {
    // Arrange — gated repositories refuse an unauthenticated request.
    container = containerWith(
      storedKeys: <ApiKeyKind, String>{ApiKeyKind.huggingFace: 'hf_abc'},
    );

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert
    check(downloader.urls.single).equals(file.downloadUrl);
    check(downloader.tokens.single).equals('hf_abc');
  });

  test('progress is published under the file id while it runs', () async {
    // Arrange
    final controller = StreamController<DownloadProgress>();
    container = containerWith(controller: controller);
    final running = notifier().start(repo: repo, file: file);

    // Act
    controller.add(const Downloading(received: 51, total: 100));
    await Future<void>.delayed(Duration.zero);

    // Assert — the chip the user tapped is the one that shows the bar.
    final progress = notifier().progressOf(file.id);
    check(progress)
        .isA<Downloading>()
        .has((p) => p.percent, 'percent')
        .equals(51);
    check(notifier().hasActiveDownload).isTrue();

    // Cleanup
    await controller.close();
    await running;
  });

  test('a second tap on a downloading chip does not start again', () async {
    // Arrange
    final controller = StreamController<DownloadProgress>();
    container = containerWith(controller: controller);
    final running = notifier().start(repo: repo, file: file);
    controller.add(const Downloading(received: 10, total: 100));
    await Future<void>.delayed(Duration.zero);

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert — two transfers of the same gigabytes would be worse than none.
    check(downloader.urls).length.equals(1);

    // Cleanup
    await controller.close();
    await running;
  });

  test('a failure is left on the chip and installs nothing', () async {
    // Arrange
    container = containerWith(
      script: <DownloadProgress>[
        const Downloading(received: 10, total: 100),
        const DownloadFailed('Connection lost'),
      ],
    );

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert
    check(notifier().progressOf(file.id)).isA<DownloadFailed>();
    check((await libraryState()).models).isEmpty();
  });

  test('a download that arrived short is refused, not installed', () async {
    // Arrange — the downloader cannot resume or cancel, so a connection that
    // drops still ends the stream as completed, with a partial file behind it.
    container = containerWith();
    await writeWeights(sizeBytes ~/ 4);

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert — caught here, the user retries a chip; missed, it surfaces much
    // later as an unreadable native error on the chat screen.
    check(notifier().progressOf(file.id)).isA<DownloadFailed>();
    check((await libraryState()).models).isEmpty();
  });

  test('the partial file is deleted so a retry starts clean', () async {
    // Arrange
    container = containerWith();
    await writeWeights(sizeBytes ~/ 4);

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert — left in place, the next attempt would find a cached model of
    // the right name and the wrong length.
    check(await File(downloadedPath).exists()).isFalse();
  });

  test('a download of the expected length still installs', () async {
    // Arrange — the guard must not reject a model that is simply finished.
    container = containerWith();

    // Act
    await notifier().start(repo: repo, file: file);

    // Assert
    check(notifier().progressOf(file.id)).isA<DownloadCompleted>();
    check((await libraryState()).models).length.equals(1);
  });

  test('dismiss clears a finished entry so the chips come back', () async {
    // Arrange
    container = containerWith();
    await notifier().start(repo: repo, file: file);

    // Act
    notifier().dismiss(file.id);

    // Assert
    check(notifier().progressOf(file.id)).isNull();
    check(notifier().hasActiveDownload).isFalse();
  });

  test('dismissing an id that was never started is harmless', () async {
    // Arrange
    container = containerWith();

    // Act
    notifier().dismiss('a/b/never.gguf');

    // Assert
    check(container.read(downloadViewModelProvider)).isEmpty();
  });
}
