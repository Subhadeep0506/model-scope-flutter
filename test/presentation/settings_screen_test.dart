import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:model_scope_flutter/config/router/app_router.dart';
import 'package:model_scope_flutter/config/theme/app_theme.dart';
import 'package:model_scope_flutter/data/models/api_keys.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
import 'package:model_scope_flutter/presentation/screens/settings_screen.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(useBundledFontsOnly);

  late FakeModelLibraryRepository library;
  late FakeAppSettingsRepository appSettings;

  /// A second installed model, named apart from [fakeInstalledModel] so the two
  /// trash buttons have distinct semantics labels.
  ModelDescriptor secondModel() => fakeInstalledModel(
    fileName: 'smollm2-360m-instruct-q4_k_m.gguf',
    name: 'SmolLM2 360M Q4',
    quantization: 'Q4_K_M',
    sizeBytes: 601 * 1000 * 1000,
  );

  /// Pumps Settings on a tall surface. The screen is seven sections deep; on
  /// the default 600-pixel window the lower ones are never laid out, so
  /// assertions about them pass or fail for the wrong reason.
  Future<void> pumpSettings(
    WidgetTester tester, {
    List<ModelDescriptor>? models,
    ThemeMode themeMode = ThemeMode.system,
    bool vision = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    library = FakeModelLibraryRepository.of(
      models ?? <ModelDescriptor>[fakeInstalledModel()],
      projectors: vision
          ? <ProjectorDescriptor>[fakeProjector()]
          : const <ProjectorDescriptor>[],
    );
    appSettings = FakeAppSettingsRepository(AppSettings(themeMode: themeMode));

    await tester.pumpWidget(
      harness(
        const SettingsScreen(),
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
          library: library,
          appSettings: appSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The `Semantics` wrapping one appearance tile, read as a widget rather than
  /// as a node so the assertion does not depend on how the tree merges.
  Semantics appearanceTile(WidgetTester tester, String label) => tester
      .widgetList<Semantics>(find.byType(Semantics))
      .firstWhere((s) => s.properties.label == '$label appearance');

  testWidgets('every section of the design is on the screen', (tester) async {
    await pumpSettings(tester);

    // The seven headings, in the order the mockups put them.
    for (final text in <String>[
      'Settings',
      'API keys',
      'Models · 399 MB',
      'Appearance',
      'Runtime defaults',
      'Storage',
      'About',
    ]) {
      check(find.text(text).evaluate(), because: text).isNotEmpty();
    }

    // And one card per credential, including the two this build only stores.
    for (final kind in ApiKeyKind.values) {
      check(find.text(kind.label).evaluate(), because: kind.label).isNotEmpty();
    }
  });

  testWidgets('the models heading adds the whole library up', (tester) async {
    // 399 MB + 601 MB, the only place the total is shown.
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    check(find.text('Models · 1.00 GB').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(find.text('SmolLM2 360M Q4').evaluate()).isNotEmpty();
  });

  testWidgets('an empty library drops the size and invites a download', (
    tester,
  ) async {
    await pumpSettings(tester, models: <ModelDescriptor>[]);

    // `Models · 0 B` would read as a fault rather than a fresh start.
    check(find.text('Models').evaluate()).isNotEmpty();
    check(find.text('No models yet. Add one to start chatting.').evaluate())
        .isNotEmpty();
    check(find.text('Browse models').evaluate()).isNotEmpty();
  });

  testWidgets('removing a model asks first, then drops the row', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Q4'));
    await tester.pumpAndSettle();
    check(find.text('Remove SmolLM2 360M Q4?').evaluate()).isNotEmpty();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pump();
    // Removal looks for the weights on disk, and real file I/O does not
    // complete inside `pump`'s fake-async zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    // The row goes, and so does its share of the heading.
    check(find.text('SmolLM2 360M Q4').evaluate()).isEmpty();
    check(find.text('Models · 399 MB').evaluate()).isNotEmpty();
    check(library.stored.models.single.id).equals(fakeInstalledModel().id);
  });

  testWidgets('a model with a projector shows a VISION chip', (tester) async {
    await pumpSettings(tester, vision: true);

    check(find.text('VISION').evaluate()).isNotEmpty();
    // The projector's bytes are part of what the device is carrying.
    check(find.text('Models · 709 MB').evaluate()).isNotEmpty();
  });

  testWidgets('without a projector there is no VISION chip', (tester) async {
    await pumpSettings(tester);

    check(find.text('VISION').evaluate()).isEmpty();
  });

  testWidgets('removing a model offers to keep its projector', (tester) async {
    await pumpSettings(tester, vision: true);

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete model'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    // The weights go; the projector stays for the next download from the
    // same repository.
    check(library.stored.models).isEmpty();
    check(library.stored.projectors).length.equals(1);
  });

  testWidgets('removing a model can take its projector too', (tester) async {
    await pumpSettings(tester, vision: true);

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Delete model and projector'),
    );
    await tester.pump();
    // Two files are deleted here, not one. Each is real I/O that only moves
    // outside the fake-async zone, so the two have to be alternated with
    // pumps that let the continuations inside it run.
    for (var turn = 0; turn < 4; turn++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    check(library.stored.models).isEmpty();
    check(library.stored.projectors).isEmpty();
  });

  testWidgets('the dialog names the models a projector is shared with', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
      vision: true,
    );

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();

    // Deleting a shared projector costs the other quant its sight, which the
    // row being removed gives no hint of.
    check(find.textContaining('shared with SmolLM2 360M Q4').evaluate())
        .isNotEmpty();
  });

  testWidgets('without a projector the dialog keeps its two buttons', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();

    check(find.widgetWithText(TextButton, 'Remove').evaluate()).isNotEmpty();
    check(
      find.widgetWithText(TextButton, 'Delete model and projector').evaluate(),
    ).isEmpty();
  });

  testWidgets('cancelling the confirmation keeps the weights', (tester) async {
    // Re-downloading gigabytes is the cost of getting this wrong.
    await pumpSettings(tester);

    await tester.tap(find.bySemanticsLabel('Remove SmolLM2 360M Instruct'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    check(find.text('SmolLM2 360M Instruct').evaluate()).isNotEmpty();
    check(library.saveCalls).equals(0);
  });

  testWidgets('Browse models opens the catalog route', (tester) async {
    // A router with a stand-in at the catalog path, so this asserts
    // where Settings sends the user rather than what the catalog renders.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: Routes.settings,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => const SettingsScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'catalog',
              builder: (_, _) => const Scaffold(body: Text('Model catalog')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(),
        ),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browse models'));
    await tester.pumpAndSettle();

    // A push, so the back button returns to Settings.
    check(find.text('Model catalog').evaluate()).isNotEmpty();
    check(router.state.matchedLocation).equals(Routes.catalog);
  });

  testWidgets('the appearance selector marks the stored mode', (tester) async {
    await pumpSettings(tester, themeMode: ThemeMode.light);

    // Selection is announced, not just drawn, so the choice is
    // readable with the screen reader on.
    check(appearanceTile(tester, 'Light').properties.selected).equals(true);
    check(appearanceTile(tester, 'Dark').properties.selected).equals(false);
    check(appearanceTile(tester, 'System').properties.selected).equals(false);
  });

  testWidgets('choosing an appearance persists it', (tester) async {
    await pumpSettings(tester, themeMode: ThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    check(appSettings.stored.themeMode).equals(ThemeMode.dark);
    check(appearanceTile(tester, 'Dark').properties.selected).equals(true);
  });

  testWidgets('tapping a row switches the model Chat answers with', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      models: <ModelDescriptor>[fakeInstalledModel(), secondModel()],
    );

    await tester.tap(find.text('SmolLM2 360M Q4'));
    await tester.pumpAndSettle();

    check(library.stored.activeId).equals(secondModel().id);
  });
}
