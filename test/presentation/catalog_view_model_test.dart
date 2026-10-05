import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/catalog_model.dart';
import 'package:model_scope_flutter/presentation/view_models/catalog_state.dart';
import 'package:model_scope_flutter/presentation/view_models/catalog_view_model.dart';

import '../support/fakes.dart';

void main() {
  late FakeCatalogRepository catalog;
  late FakeHuggingFaceRepository hub;
  late ProviderContainer container;

  /// The shipped manifest, as these tests pretend it was authored.
  List<CatalogModel> seed() => <CatalogModel>[
    fakeCatalogModel(
      repoId: 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
      name: 'Qwen2.5 Coder 1.5B Instruct',
      capabilities: const <ModelCapability>[
        ModelCapability.textToText,
        ModelCapability.toolCalling,
      ],
    ),
    fakeCatalogModel(
      repoId: 'ggml-org/SmolVLM-2B-Instruct-GGUF',
      name: 'SmolVLM 2B Instruct',
      capabilities: const <ModelCapability>[ModelCapability.imageToText],
    ),
    fakeCatalogModel(
      repoId: 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
      name: 'TinyLlama 1.1B Chat',
      capabilities: const <ModelCapability>[ModelCapability.textToText],
    ),
  ];

  void build({List<CatalogModel>? models, Object? failure}) {
    catalog = FakeCatalogRepository(models: models ?? seed(), failure: failure);
    hub = FakeHuggingFaceRepository();
    container = ProviderContainer.test(
      retry: noRetry,
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(),
        catalog: catalog,
        huggingFace: hub,
      ),
    );
  }

  CatalogViewModel notifier() =>
      container.read(catalogViewModelProvider.notifier);

  Future<CatalogState> state() =>
      container.read(catalogViewModelProvider.future);

  List<String> visibleNames(CatalogState state) =>
      state.visible.map((model) => model.name).toList();

  test('loads the whole manifest before anything is typed', () async {
    build();

    final loaded = await state();

    check(loaded.models).length.equals(3);
    check(loaded.overline).equals('3 REPOSITORIES · GGUF');
    check(loaded.resultsLabel).equals('3 results');
  });

  test('browsing the catalog costs no network at all', () async {
    // This is the whole reason the manifest ships with the app.
    build();
    await state();

    notifier().search('qwen');
    notifier().filterBy(ModelCapability.toolCalling);
    notifier().search('');

    // The Hub is only asked about a repository the user opens.
    check(hub.detailRequests).isEmpty();
    check(hub.fileRequests).isEmpty();
    check(catalog.loadCalls).equals(1);
  });

  test('search narrows on the title', () async {
    build();
    await state();

    notifier().search('tiny');

    check(visibleNames(await state()))
        .deepEquals(<String>['TinyLlama 1.1B Chat']);
  });

  test('search also finds a publisher', () async {
    // The mockup's hint is `Search models or publishers`.
    build();
    await state();

    notifier().search('bartowski');

    check(visibleNames(await state()))
        .deepEquals(<String>['Qwen2.5 Coder 1.5B Instruct']);
  });

  test('search ignores case and surrounding spaces', () async {
    // A pasted repository name brings both along.
    build();
    await state();

    notifier().search('  SMOLVLM  ');

    check(visibleNames(await state()))
        .deepEquals(<String>['SmolVLM 2B Instruct']);
  });

  test('a query that matches nothing empties the list', () async {
    build();
    await state();

    notifier().search('llama-70b');

    // The screen needs this to draw its empty state.
    check((await state()).visible).isEmpty();
    check((await state()).resultsLabel).equals('0 results');
  });

  test('a capability chip keeps only the models that claim it', () async {
    build();
    await state();

    notifier().filterBy(ModelCapability.imageToText);

    check(visibleNames(await state()))
        .deepEquals(<String>['SmolVLM 2B Instruct']);
  });

  test('the chip and the search field narrow together', () async {
    build();
    await state();

    // Text-to-text matches two rows; the query leaves one.
    notifier().filterBy(ModelCapability.textToText);
    notifier().search('tiny');

    check(visibleNames(await state()))
        .deepEquals(<String>['TinyLlama 1.1B Chat']);
  });

  test('All clears the capability without clearing the query', () async {
    build();
    await state();
    notifier().search('instruct');
    notifier().filterBy(ModelCapability.imageToText);

    // `All` is the null chip.
    notifier().filterBy(null);

    check((await state()).capability).isNull();
    check((await state()).query).equals('instruct');
    check(visibleNames(await state())).deepEquals(<String>[
      'Qwen2.5 Coder 1.5B Instruct',
      'SmolVLM 2B Instruct',
    ]);
  });

  test('the overline counts the catalog, not the filtered view', () async {
    // It describes what the app offers, not what is on screen.
    build();
    await state();

    notifier().search('tiny');

    check((await state()).overline).equals('3 REPOSITORIES · GGUF');
    check((await state()).resultsLabel).equals('1 result');
  });

  test(
    'a corrupt manifest surfaces as an error the screen can retry',
    () async {
      // Only a broken build can cause this, but the screen still
      // offers a button rather than dead-ending on a spinner.
      build(
        failure: const FormatException('The model catalog must be a list.'),
      );

      await check(state()).throws<FormatException>();

      check(container.read(catalogViewModelProvider).hasError).isTrue();
    },
  );

  test('retry reloads the manifest after a failed build', () async {
    build(failure: const FormatException('bad manifest'));
    await check(state()).throws<FormatException>();

    // As if the next build shipped a good file.
    catalog.failure = null;
    await notifier().retry();

    check((await state()).models).length.equals(3);
    check(catalog.loadCalls).equals(2);
  });
}
