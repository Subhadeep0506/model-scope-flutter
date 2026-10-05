import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/data/sources/hf_api_client.dart';
import 'package:model_scope_flutter/data/models/download_progress.dart';
import 'package:model_scope_flutter/presentation/widgets/model_detail_sheet.dart';
import 'package:model_scope_flutter/presentation/widgets/model_file_row.dart';
import 'package:model_scope_flutter/presentation/widgets/square_icon_button.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeHuggingFaceRepository hub;
  late FakeModelDownloader downloader;

  final CatalogModel model = fakeCatalogModel(
    repoId: 'ggml-org/SmolVLM-2B-Instruct-GGUF',
    name: 'SmolVLM 2B Instruct',
    capabilities: const <ModelCapability>[ModelCapability.imageToText],
  );

  GgufFile fileIn({
    required String fileName,
    int sizeBytes = 399 * 1000 * 1000,
    GgufFileKind kind = GgufFileKind.model,
  }) => fakeGgufFile(
    repoId: model.repoId,
    fileName: fileName,
    sizeBytes: sizeBytes,
    kind: kind,
  );

  final GgufFile quant = fileIn(fileName: 'smolvlm-2b-instruct-q4_k_m.gguf');
  final GgufFile projector = fileIn(
    fileName: 'mmproj-smolvlm-f16.gguf',
    sizeBytes: 190 * 1000 * 1000,
    kind: GgufFileKind.mmproj,
  );

  /// The square control carrying [label]. Found as a widget, not through the
  /// semantics tree: [SquareIconButton] annotates its subtree rather than
  /// forming a node of its own, so `find.bySemanticsLabel` does not see it.
  Finder control(String label) => find.byWidgetPredicate(
    (widget) => widget is SquareIconButton && widget.label == label,
  );

  /// Taps the download button and lets the tap's async work land. Deliberately
  /// not `pumpAndSettle`: a queued transfer draws an indeterminate bar that
  /// animates forever, so waiting for the tree to go still never returns.
  Future<void> tapDownload(WidgetTester tester) async {
    await tester.tap(control('Download Q4_K_M'));
    await tester.pump();
    await tester.pump();
  }

  /// Pumps the sheet on a tall surface, already open.
  Future<void> pumpSheet(
    WidgetTester tester, {
    List<GgufFile>? files,
    Object? filesFailure,
    FakeModelLibraryRepository? library,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    hub = FakeHuggingFaceRepository(
      files: <String, List<GgufFile>>{
        model.repoId: files ?? <GgufFile>[quant, projector],
      },
      filesFailure: filesFailure,
    );
    downloader = FakeModelDownloader();

    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ModelDetailSheet.show(context, model),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        retry: noRetry,
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          huggingFace: hub,
          downloader: downloader,
          library: library ?? FakeModelLibraryRepository(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every file the repository holds', (tester) async {
    await pumpSheet(tester);

    // The point of the sheet is that the contents are not a mystery.
    check(tester.widgetList<ModelFileRow>(find.byType(ModelFileRow))).length
        .equals(2);
    check(find.text(quant.fileName).evaluate()).isNotEmpty();
    check(find.text(projector.fileName).evaluate()).isNotEmpty();
    check(find.text('SmolVLM 2B Instruct').evaluate()).isNotEmpty();
    check(find.text(model.repoId).evaluate()).isNotEmpty();
  });

  testWidgets('the file tree is fetched once, when the sheet opens', (
    tester,
  ) async {
    await pumpSheet(tester);

    // This is the only request the whole catalog flow makes per model.
    check(hub.fileRequests).deepEquals(<String>[model.repoId]);
  });

  testWidgets('both a quant row and a projector row offer a download', (
    tester,
  ) async {
    await pumpSheet(tester);

    // A projector is what gives the quants here their sight, so it is fetched
    // the same way the weights are.
    check(control('Download Q4_K_M').evaluate()).isNotEmpty();
    check(control('Download F16').evaluate()).isNotEmpty();
    check(control('About ${projector.fileName}').evaluate()).isEmpty();
  });

  testWidgets('tapping download on a projector starts that file', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(control('Download F16'));
    await tester.pump();
    await tester.pump();

    check(downloader.started.single.fileName).equals(projector.fileName);
  });

  testWidgets('an installed projector is marked rather than offered', (
    tester,
  ) async {
    // A repository holds one projector, so once it is in there is nothing
    // left to fetch.
    await pumpSheet(
      tester,
      library: FakeModelLibraryRepository.of(
        const <ModelDescriptor>[],
        projectors: <ProjectorDescriptor>[
          fakeProjector(repoId: model.repoId, fileName: projector.fileName),
        ],
      ),
    );

    check(control('Download F16').evaluate()).isEmpty();
    check(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Icon &&
                widget.semanticLabel == '${projector.fileName} is installed',
          )
          .evaluate(),
    ).isNotEmpty();
  });

  testWidgets('an adapter is still listed for reference only', (tester) async {
    final adapter = fileIn(
      fileName: 'smolvlm-lora-f16.gguf',
      kind: GgufFileKind.adapter,
    );
    await pumpSheet(tester, files: <GgufFile>[quant, adapter]);

    await tester.tap(control('About ${adapter.fileName}'));
    await tester.pumpAndSettle();

    check(find.text('Adapter file').evaluate()).isNotEmpty();
    check(downloader.started).isEmpty();
  });

  testWidgets('tapping download starts exactly that file', (tester) async {
    await pumpSheet(tester);

    await tapDownload(tester);

    check(downloader.started.single.fileName).equals(quant.fileName);
    check(downloader.displayNames.single).equals(model.name);
  });

  testWidgets('a running download replaces the button with controls', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tapDownload(tester);

    // As the platform would report it.
    downloader.emit(
      quant.id,
      const Downloading(fraction: 0.42, canPause: true),
    );
    await tester.pumpAndSettle();

    // The transfer belongs to the system now, so the row has to offer
    // pause and cancel rather than only a percentage.
    check(find.text('downloading 42%').evaluate()).isNotEmpty();
    check(control('Pause download').evaluate()).isNotEmpty();
    check(control('Cancel download').evaluate()).isNotEmpty();
  });

  testWidgets('pause is withheld when the transfer cannot resume', (
    tester,
  ) async {
    // A redirect can land on a CDN that ignores range requests, and
    // a pause button that silently restarts a gigabyte is worse than none.
    await pumpSheet(tester);
    await tapDownload(tester);

    downloader.emit(quant.id, const Downloading(fraction: 0.42));
    await tester.pumpAndSettle();

    check(control('Pause download').evaluate()).isEmpty();
    check(control('Cancel download').evaluate()).isNotEmpty();
  });

  testWidgets('a paused download offers to carry on', (tester) async {
    await pumpSheet(tester);
    await tapDownload(tester);
    downloader.emit(
      quant.id,
      const DownloadPaused(fraction: 0.42, totalBytes: 1000000000),
    );
    await tester.pumpAndSettle();

    await tester.tap(control('Resume download'));
    await tester.pumpAndSettle();

    // The caption says what finishing would still cost.
    check(find.text('paused · 420 MB of 1.00 GB').evaluate()).isNotEmpty();
    check(downloader.resumes.single).equals(quant.id);
  });

  testWidgets('a failure is dismissible, which restores the button', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tapDownload(tester);
    downloader.emit(quant.id, const DownloadFailed('Connection lost'));
    await tester.pumpAndSettle();
    check(find.text('Connection lost').evaluate()).isNotEmpty();

    await tester.tap(control('Dismiss'));
    await tester.pumpAndSettle();

    // A dead end would leave the user no way to try again.
    check(find.text('Connection lost').evaluate()).isEmpty();
    check(control('Download Q4_K_M').evaluate()).isNotEmpty();
  });

  testWidgets('a repository with no GGUF files says so', (tester) async {
    await pumpSheet(tester, files: <GgufFile>[]);

    check(
      find
          .text('This repository holds no GGUF files the app can load.')
          .evaluate(),
    ).isNotEmpty();
  });

  testWidgets('an unreachable Hub offers a retry, not a blank sheet', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      filesFailure: const HfApiException('Hugging Face is rate-limiting'),
    );

    check(find.textContaining('Could not reach Hugging Face').evaluate())
        .isNotEmpty();
    check(find.widgetWithText(TextButton, 'Retry').evaluate()).isNotEmpty();
  });

  testWidgets('the control sits flush with the card edge', (tester) async {
    await pumpSheet(tester);

    // The file name is stretched across the card, so its right edge is the
    // card's content edge — what the button and the size are meant to meet.
    final contentEdge = tester.getTopRight(find.text(quant.fileName)).dx;

    check(tester.getTopRight(control('Download Q4_K_M')).dx)
        .isCloseTo(contentEdge, 0.5);
  });

  testWidgets('every row puts its control at the same edge', (tester) async {
    // Quant labels of different widths used to shift the button by
    // the difference, because the row's leftover space was parked at its end.
    await pumpSheet(
      tester,
      files: <GgufFile>[
        fileIn(fileName: 'smolvlm-2b-instruct-q4_k_m.gguf'),
        fileIn(fileName: 'smolvlm-2b-instruct-q8_0.gguf'),
        projector,
      ],
    );

    final edges = <double>{
      tester.getTopRight(control('Download Q4_K_M')).dx,
      tester.getTopRight(control('Download Q8_0')).dx,
      tester.getTopRight(control('Download F16')).dx,
    };

    // One shared edge down the whole list.
    check(edges).length.equals(1);
  });
}
