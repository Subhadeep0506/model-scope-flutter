import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/hf_repo_summary.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';
import 'package:model_scope_flutter/domain/services/model_downloader.dart';
import 'package:model_scope_flutter/presentation/widgets/add_model_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/quant_chip.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeHuggingFaceRepository catalog;
  late FakeModelDownloader downloader;
  late FakeModelLibraryRepository library;

  /// Advances a fixed number of frames instead of settling.
  ///
  /// The sheet shows an indeterminate spinner whenever another page is on its
  /// way, and `pumpAndSettle` waits for animations to stop — which, with a
  /// spinner on screen, is never.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Twelve repos, far more than the 600-pixel test window can show — which is
  /// the point: only the visible ones should cost a file-tree request.
  List<HfRepoSummary> manyRepos() => <HfRepoSummary>[
    for (var i = 0; i < 12; i++) fakeRepo(id: 'owner/repo-$i'),
  ];

  /// A quant list for every repo in [repos], so any card that resolves has
  /// something to draw.
  Map<String, List<GgufFile>> filesFor(List<HfRepoSummary> repos) =>
      <String, List<GgufFile>>{
        for (final repo in repos)
          repo.id: <GgufFile>[fakeGgufFile(repoId: repo.id)],
      };

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<HfRepoPage>? pages,
    Map<String, List<GgufFile>>? files,
    Object? filesFailure,
    StreamController<DownloadProgress>? controller,
  }) async {
    catalog = FakeHuggingFaceRepository(
      pages:
          pages ??
          <HfRepoPage>[
            HfRepoPage(items: <HfRepoSummary>[fakeRepo()], nextCursor: null),
          ],
      files: files ?? filesFor(<HfRepoSummary>[fakeRepo()]),
      filesFailure: filesFailure,
    );
    downloader = FakeModelDownloader()..controller = controller;
    library = FakeModelLibraryRepository();

    await tester.pumpWidget(
      harness(
        const Scaffold(body: AddModelSheet()),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          huggingFace: catalog,
          downloader: downloader,
          library: library,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets('the sheet lists what the catalog returned', (tester) async {
    // Arrange / Act
    await pumpSheet(tester);

    // Assert
    check(find.text('Hugging Face · GGUF').evaluate()).isNotEmpty();
    check(find.text('HuggingFaceTB/SmolLM2-360M-Instruct-GGUF').evaluate())
        .isNotEmpty();
    check(find.text('182k downloads · 412 likes').evaluate()).isNotEmpty();
  });

  testWidgets('the quant chips arrive once the file tree resolves', (
    tester,
  ) async {
    // Arrange / Act
    await pumpSheet(tester);

    // Assert — `GET /api/models` carries no file names or sizes, so the chip
    // label can only come from the second, per-repo request.
    check(catalog.fileRequests)
        .contains('HuggingFaceTB/SmolLM2-360M-Instruct-GGUF');
    check(find.text('Q8_0 · 399 MB').evaluate()).isNotEmpty();
  });

  testWidgets('a repo below the fold costs no request until it is seen', (
    tester,
  ) async {
    // Arrange — laziness is the only thing keeping an unauthenticated browse
    // under Hugging Face's rate limit.
    final repos = manyRepos();

    // Act
    await pumpSheet(
      tester,
      pages: <HfRepoPage>[HfRepoPage(items: repos, nextCursor: null)],
      files: filesFor(repos),
    );

    // Assert
    check(catalog.fileRequests).contains('owner/repo-0');
    check(catalog.fileRequests).not((it) => it.contains('owner/repo-11'));
  });

  testWidgets('tapping a chip starts the download and shows the bar', (
    tester,
  ) async {
    // Arrange — a hand-driven stream, so the download can be caught mid-flight
    // rather than already finished.
    final controller = StreamController<DownloadProgress>();
    await pumpSheet(tester, controller: controller);
    addTearDown(controller.close);

    // Act
    await tester.tap(find.byType(QuantChip));
    await pumpFrames(tester, 2);
    controller.add(const Downloading(received: 51, total: 100));
    await pumpFrames(tester, 2);

    // Assert — the bar appears under the chips of the card that was tapped.
    check(downloader.urls.single).equals(fakeGgufFile().downloadUrl);
    check(find.text('downloading 51%').evaluate()).isNotEmpty();
    check(find.byType(LinearProgressIndicator).evaluate()).isNotEmpty();
  });

  testWidgets('reaching the end of the list fetches one more page', (
    tester,
  ) async {
    // Arrange — a full page, so the list is long enough to scroll.
    final first = manyRepos();
    final second = <HfRepoSummary>[fakeRepo(id: 'owner/last')];
    await pumpSheet(
      tester,
      pages: <HfRepoPage>[
        HfRepoPage(items: first, nextCursor: '1'),
        HfRepoPage(items: second, nextCursor: null),
      ],
      files: filesFor(<HfRepoSummary>[...first, ...second]),
    );
    final before = catalog.searches.length;

    // Act — to the end, then on to the end of the page that arrived.
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await pumpFrames(tester, 16);
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await pumpFrames(tester, 16);

    // Assert — the scroll listener fires on every frame, so the guard inside
    // `loadMore` is what keeps this at one request rather than dozens.
    check(catalog.searches.length - before).equals(1);
    check(catalog.searches.last.cursor).equals('1');
    check(find.text('End of results').evaluate()).isNotEmpty();
  });

  testWidgets('a rate-limited file tree is reported on its own card', (
    tester,
  ) async {
    // Arrange / Act — the list still renders; only the chips are missing.
    await pumpSheet(
      tester,
      filesFailure: const HfApiException(
        'Too many requests',
        isRateLimit: true,
      ),
    );

    // Assert
    check(find.text('HuggingFaceTB/SmolLM2-360M-Instruct-GGUF').evaluate())
        .isNotEmpty();
    check(
      find
          .text('Hugging Face is rate-limiting — add a token in API keys.')
          .evaluate(),
    ).isNotEmpty();
    check(find.text('Retry').evaluate()).isNotEmpty();
  });

  testWidgets('a failed search offers a retry instead of an empty list', (
    tester,
  ) async {
    // Arrange
    await pumpSheet(tester);
    catalog.failure = const HfApiException('No connection to Hugging Face.');

    // Act — type a query, then wait out the 350 ms debounce.
    await tester.enterText(find.byType(TextField).first, 'qwen');
    await tester.pump(const Duration(milliseconds: 400));
    await pumpFrames(tester);

    // Assert — an empty list would read as "no models match".
    check(find.text('No connection to Hugging Face.').evaluate()).isNotEmpty();
    check(find.text('Try again').evaluate()).isNotEmpty();
  });
}
