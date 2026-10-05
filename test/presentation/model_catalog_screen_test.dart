import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/data/models/gguf_file.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/presentation/screens/model_catalog_screen.dart';
import 'package:model_scope_flutter/presentation/widgets/catalog_model_card.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeCatalogRepository catalog;
  late FakeHuggingFaceRepository hub;

  const String qwenId = 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF';
  const String smolVlmId = 'ggml-org/SmolVLM-2B-Instruct-GGUF';

  List<CatalogModel> seed() => <CatalogModel>[
    fakeCatalogModel(
      repoId: qwenId,
      name: 'Qwen2.5 Coder 1.5B Instruct',
      description: 'Compact code generation and structured output.',
      paramLabel: '1.5B',
      capabilities: const <ModelCapability>[
        ModelCapability.textToText,
        ModelCapability.toolCalling,
      ],
    ),
    fakeCatalogModel(
      repoId: smolVlmId,
      name: 'SmolVLM 2B Instruct',
      description: 'Reads images and answers questions about them.',
      paramLabel: '2B',
      capabilities: const <ModelCapability>[ModelCapability.imageToText],
    ),
  ];

  /// Pumps the catalog on a tall surface. On the default 600-pixel window the
  /// second card is never laid out, so assertions about it pass or fail for the
  /// wrong reason.
  Future<void> pumpCatalog(
    WidgetTester tester, {
    List<CatalogModel>? models,
    List<ModelDescriptor>? installed,
    Object? failure,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    catalog = FakeCatalogRepository(models: models ?? seed(), failure: failure);
    hub = FakeHuggingFaceRepository(
      files: <String, List<GgufFile>>{
        qwenId: <GgufFile>[fakeGgufFile(repoId: qwenId)],
      },
    );

    await tester.pumpWidget(
      harness(
        const ModelCatalogScreen(),
        retry: noRetry,
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          catalog: catalog,
          huggingFace: hub,
          library: FakeModelLibraryRepository.of(
            installed ?? const <ModelDescriptor>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws one card per manifest entry', (tester) async {
    await pumpCatalog(tester);

    check(tester.widgetList<CatalogModelCard>(find.byType(CatalogModelCard)))
        .length
        .equals(2);
    check(find.text('Qwen2.5 Coder 1.5B Instruct').evaluate()).isNotEmpty();
    check(find.text('SmolVLM 2B Instruct').evaluate()).isNotEmpty();
    check(find.text('Model catalog').evaluate()).isNotEmpty();
  });

  testWidgets('the heading counts the catalog and the results', (tester) async {
    await pumpCatalog(tester);

    check(find.text('2 REPOSITORIES · GGUF').evaluate()).isNotEmpty();
    check(find.text('Available models').evaluate()).isNotEmpty();
    check(find.text('2 results').evaluate()).isNotEmpty();
  });

  testWidgets('the card shows what the manifest knows about the model', (
    tester,
  ) async {
    await pumpCatalog(tester);

    // The repository id, the parameter count and both capabilities.
    check(find.text(qwenId).evaluate()).isNotEmpty();
    check(find.text('1.5B').evaluate()).isNotEmpty();
    check(find.text('Tool calling').evaluate()).isNotEmpty();
    check(find.text('Image to text').evaluate()).isNotEmpty();
  });

  testWidgets('live stats fill in behind the manifest', (tester) async {
    // The only network this screen makes.
    await pumpCatalog(tester);

    // One call per card, and nothing fetches a file tree.
    check(hub.detailRequests).unorderedEquals(<String>[qwenId, smolVlmId]);
    check(hub.fileRequests).isEmpty();
    check(find.text('182k').evaluate()).isNotEmpty();
  });

  testWidgets('typing narrows the list without asking the Hub again', (
    tester,
  ) async {
    await pumpCatalog(tester);
    final before = hub.detailRequests.length;

    await tester.enterText(find.byType(TextField), 'smolvlm');
    await tester.pumpAndSettle();

    // The old build searched the Hub on every keystroke.
    check(find.text('SmolVLM 2B Instruct').evaluate()).isNotEmpty();
    check(find.text('Qwen2.5 Coder 1.5B Instruct').evaluate()).isEmpty();
    check(find.text('1 result').evaluate()).isNotEmpty();
    check(hub.detailRequests).length.equals(before);
  });

  testWidgets('a capability chip narrows the list', (tester) async {
    await pumpCatalog(tester);

    await tester.tap(find.bySemanticsLabel('Image to text models'));
    await tester.pumpAndSettle();

    check(find.text('SmolVLM 2B Instruct').evaluate()).isNotEmpty();
    check(find.text('Qwen2.5 Coder 1.5B Instruct').evaluate()).isEmpty();
  });

  testWidgets('a search with no matches says so', (tester) async {
    await pumpCatalog(tester);

    await tester.enterText(find.byType(TextField), 'llama-70b');
    await tester.pumpAndSettle();

    // An empty list with no explanation reads as a broken screen.
    check(find.text('No models match that search.').evaluate()).isNotEmpty();
  });

  testWidgets('a model already in the library is badged', (tester) async {
    // The user should not download the same repository twice.
    await pumpCatalog(
      tester,
      installed: <ModelDescriptor>[fakeInstalledModel(repoId: qwenId)],
    );

    // One badge, on the row that owns it.
    check(find.text('Installed').evaluate()).length.equals(1);
  });

  testWidgets('tapping a card opens its file sheet', (tester) async {
    await pumpCatalog(tester);

    await tester.tap(find.text('Qwen2.5 Coder 1.5B Instruct'));
    await tester.pumpAndSettle();

    // The quants arrive only now, so opening a model is one request
    // and browsing the list is none.
    check(find.text('Available files').evaluate()).isNotEmpty();
    check(hub.fileRequests).deepEquals(<String>[qwenId]);
  });

  testWidgets('a corrupt manifest offers a retry', (tester) async {
    await pumpCatalog(
      tester,
      failure: const FormatException('The model catalog must be a list.'),
    );

    check(find.text('The model catalog could not be read.').evaluate())
        .isNotEmpty();
    check(find.widgetWithText(TextButton, 'Retry').evaluate()).isNotEmpty();
  });
}
