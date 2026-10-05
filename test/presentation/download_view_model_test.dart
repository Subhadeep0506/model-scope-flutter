import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/data/models/download_progress.dart';
import 'package:model_scope_flutter/presentation/view_models/download_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeModelDownloader downloader;
  late ProviderContainer container;
  late Directory directory;
  late String downloadedPath;

  /// Stands in for the finished file. Small, but real: a fictional path would
  /// take the could-not-measure branch instead of the one under test.
  const int sizeBytes = 2048;

  final CatalogModel model = fakeCatalogModel();
  final GgufFile file = fakeGgufFile(sizeBytes: sizeBytes);
  final GgufFile second = fakeGgufFile(
    fileName: 'smollm2-360m-instruct-q4_k_m.gguf',
    sizeBytes: sizeBytes,
  );
  final GgufFile projector = fakeGgufFile(
    fileName: 'mmproj-BF16.gguf',
    sizeBytes: sizeBytes,
    kind: GgufFileKind.mmproj,
  );
  final GgufFile otherProjector = fakeGgufFile(
    fileName: 'mmproj-F16.gguf',
    sizeBytes: sizeBytes,
    kind: GgufFileKind.mmproj,
  );

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
    Map<ApiKeyKind, String>? storedKeys,
    Map<String, DownloadProgress>? restored,
  }) {
    downloader = FakeModelDownloader(
      restored: restored ?? const <String, DownloadProgress>{},
    );
    return ProviderContainer.test(
      retry: noRetry,
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(),
        downloader: downloader,
        // An empty library: these tests are about what a download puts in it.
        library: FakeModelLibraryRepository(),
        apiKeys: FakeApiKeyRepository(storedKeys),
        // The expected size is read back from the file tree before a finished
        // download is recorded, so the repository has to know these files.
        huggingFace: FakeHuggingFaceRepository(
          files: <String, List<GgufFile>>{
            model.repoId: <GgufFile>[file, second, projector, otherProjector],
          },
        ),
      ),
    );
  }

  DownloadViewModel notifier() =>
      container.read(downloadViewModelProvider.notifier);

  Future<ModelLibrary> libraryState() =>
      container.read(modelLibraryViewModelProvider.future);

  /// Waits for the view model to stop moving [id] along. Real disk I/O takes an
  /// unknown number of event-loop turns, so this waits on the state rather than
  /// on a fixed amount of pumping, which goes flaky on a loaded CI runner.
  Future<void> settle(String id) async {
    for (var turn = 0; turn < 200; turn++) {
      final progress = notifier().progressOf(id);
      if (progress is DownloadCompleted || progress is DownloadFailed) break;
      await pumpEventQueue(times: 1);
    }
    // The library write is started after the row turns green, so give it a
    // turn of its own.
    await pumpEventQueue();
  }

  /// Runs a download to completion, as the platform reports it.
  Future<void> finish(GgufFile which, {String? path}) async {
    await notifier().start(model: model, file: which);
    downloader.emit(which.id, DownloadCompleted(path ?? downloadedPath));
    await settle(which.id);
  }

  test('a completed download is recorded in the library', () async {
    container = containerWith();

    await finish(file);

    // The path is the downloader's, not a guess at where it put it.
    final installed = (await libraryState()).models.single;
    check(installed.id).equals(file.id);
    check(installed.localPath).equals(downloadedPath);
    check(installed.quantization).equals('Q8_0');
    check(installed.sizeBytes).equals(file.sizeBytes);
    check(installed.name).equals('SmolLM2 360M Instruct');
  });

  test('the first download becomes the active model', () async {
    // Nothing installed, so Chat has nothing to answer with.
    container = containerWith();

    await finish(file);

    // One tap, not two, to get from empty to usable.
    check((await libraryState()).activeId).equals(file.id);
  });

  test('a later download does not steal the active model', () async {
    container = containerWith();
    await finish(file);

    await finish(second);

    check((await libraryState()).models).length.equals(2);
    check((await libraryState()).activeId).equals(file.id);
  });

  test('a downloaded projector is recorded against its repository', () async {
    container = containerWith();

    await finish(projector);

    final library = await libraryState();
    // It is not a model: it holds no weights and cannot answer anything.
    check(library.models).isEmpty();
    final installed = library.projectorFor(model.repoId);
    check(installed?.fileName).equals(projector.fileName);
    check(installed?.localPath).equals(downloadedPath);
    check(library.activeId).isNull();
  });

  test('a projector gives every installed quant of its repo vision', () async {
    container = containerWith();
    await finish(file);
    await finish(second);

    await finish(projector);

    final library = await libraryState();
    check(library.hasVision(library.models.first)).isTrue();
    check(library.hasVision(library.models.last)).isTrue();
  });

  test('a second projector replaces the first', () async {
    container = containerWith();
    await finish(projector);

    await finish(otherProjector);

    final library = await libraryState();
    check(library.projectors).length.equals(1);
    check(library.projectorFor(model.repoId)?.fileName)
        .equals(otherProjector.fileName);
  });

  test('the Hugging Face token is passed to the downloader', () async {
    // Gated repositories refuse an unauthenticated request.
    container = containerWith(
      storedKeys: <ApiKeyKind, String>{ApiKeyKind.huggingFace: 'hf_abc'},
    );

    await notifier().start(model: model, file: file);

    check(downloader.started.single.id).equals(file.id);
    check(downloader.tokens.single).equals('hf_abc');
    check(downloader.displayNames.single).equals(model.name);
  });

  test('a queued download is published before any bytes arrive', () async {
    container = containerWith();

    await notifier().start(model: model, file: file);

    // The row must change on the tap, not when the platform
    // eventually gets round to the transfer.
    check(notifier().progressOf(file.id)).isA<DownloadQueued>();
  });

  test('progress is published under the file id while it runs', () async {
    container = containerWith();
    await notifier().start(model: model, file: file);

    downloader.emit(file.id, const Downloading(fraction: 0.51));
    await pumpEventQueue();

    // The row the user tapped is the one that shows the bar.
    final progress = notifier().progressOf(file.id);
    check(progress)
        .isA<Downloading>()
        .has((p) => p.percent, 'percent')
        .equals(51);
    check(notifier().hasActiveDownload).isTrue();
  });

  test('a second tap on a running download does not start again', () async {
    container = containerWith();
    await notifier().start(model: model, file: file);
    downloader.emit(file.id, const Downloading(fraction: 0.1));
    await pumpEventQueue();

    await notifier().start(model: model, file: file);

    // Two transfers of the same gigabytes would be worse than none.
    check(downloader.started).length.equals(1);
  });

  test('a paused download is not restarted by another tap', () async {
    // The row still shows a button, and a pause is not an invitation
    // to begin again from zero.
    container = containerWith();
    await notifier().start(model: model, file: file);
    downloader.emit(file.id, const DownloadPaused(fraction: 0.4));
    await pumpEventQueue();

    await notifier().start(model: model, file: file);

    check(downloader.started).length.equals(1);
  });

  test('pause, resume and cancel reach the downloader', () async {
    container = containerWith();
    await notifier().start(model: model, file: file);

    await notifier().pause(file.id);
    await notifier().resume(file.id);
    await notifier().cancel(file.id);

    // The platform owns the transfer, so these have to be forwarded
    // rather than simulated in the view model.
    check(downloader.pauses.single).equals(file.id);
    check(downloader.resumes.single).equals(file.id);
    check(downloader.cancels.single).equals(file.id);
  });

  test('a cancelled transfer leaves the row empty', () async {
    container = containerWith();
    await notifier().start(model: model, file: file);

    downloader.emit(file.id, const DownloadCancelled());
    await pumpEventQueue();

    // The user asked for it to stop, so nothing is left to dismiss.
    check(notifier().progressOf(file.id)).isNull();
  });

  test('transfers the system kept running are picked back up', () async {
    // The app was closed mid-download and the OS carried on.
    container = containerWith(
      restored: <String, DownloadProgress>{
        file.id: const Downloading(fraction: 0.62),
      },
    );

    notifier();
    await pumpEventQueue();

    // The row comes back at its real percentage, not at zero.
    check(notifier().progressOf(file.id))
        .isA<Downloading>()
        .has((p) => p.percent, 'percent')
        .equals(62);
  });

  test('a failed restore leaves the view model usable', () async {
    container = containerWith();
    downloader.restoreFailure = StateError('database unreadable');

    notifier();
    await pumpEventQueue();

    // A broken tracking database must not take the sheet with it.
    check(container.read(downloadViewModelProvider)).isEmpty();
  });

  test('a failure is left on the row and installs nothing', () async {
    container = containerWith();
    await notifier().start(model: model, file: file);

    downloader.emit(file.id, const DownloadFailed('Connection lost'));
    await pumpEventQueue();

    check(notifier().progressOf(file.id)).isA<DownloadFailed>();
    check((await libraryState()).models).isEmpty();
  });

  test('a download that arrived short is refused, not installed', () async {
    // The platform verifies the content length itself, so this is
    // belt and braces against a truncated file reaching the loader.
    container = containerWith();
    await writeWeights(sizeBytes ~/ 4);

    await finish(file);

    // Caught here, the user retries a row; missed, it surfaces much
    // later as an unreadable native error on the chat screen.
    check(notifier().progressOf(file.id)).isA<DownloadFailed>();
    check((await libraryState()).models).isEmpty();
  });

  test('the partial file is deleted so a retry starts clean', () async {
    container = containerWith();
    await writeWeights(sizeBytes ~/ 4);

    await finish(file);

    // Left in place, the next attempt would find a model of the right
    // name and the wrong length.
    check(await File(downloadedPath).exists()).isFalse();
  });

  test('a download of the expected length still installs', () async {
    // The guard must not reject a model that is simply finished.
    container = containerWith();

    await finish(file);

    check(notifier().progressOf(file.id)).isA<DownloadCompleted>();
    check((await libraryState()).models).length.equals(1);
  });

  test('dismiss clears a finished entry so the button comes back', () async {
    container = containerWith();
    await finish(file);

    notifier().dismiss(file.id);

    check(notifier().progressOf(file.id)).isNull();
    check(notifier().hasActiveDownload).isFalse();
  });

  test('dismissing an id that was never started is harmless', () async {
    container = containerWith();

    notifier().dismiss('a/b/never.gguf');

    check(container.read(downloadViewModelProvider)).isEmpty();
  });
}
